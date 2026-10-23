import Foundation
import CryptoKit
import Darwin

/// A reverse, content-defined-chunk recipe. References read only the exact verified
/// output; literals contain bounded original boundary/metadata fragments.
struct ReverseDelta:Codable {
    struct Part:Codable {var offset:UInt64?;var count:Int;var literal:Data?}
    var parts:[Part]
    var literalBytes:Int {parts.reduce(0) {$0+($1.literal?.count ?? 0)}}
    static let maximumPayload=24*1024*1024
    static func capture(original:URL,output:URL) throws -> ReverseDelta {
        let reader=FileIdentityReader(),before=try reader.fingerprint(at:original),after=try reader.fingerprint(at:output)
        if before.contentHash==after.contentHash {return .init(parts:before.snapshot.id.size==0 ? []:[.init(offset:0,count:Int(before.snapshot.id.size),literal:nil)])}
        // Tiny media has no CDC boundary; a bounded common prefix/suffix recipe
        // preserves its unchanged encoded payload rather than storing a whole file.
        if before.snapshot.id.size<=131072,after.snapshot.id.size<=262144 {
            let a=try Data(contentsOf:original),b=try Data(contentsOf:output)
            var prefix=0,suffix=0
            while prefix<min(a.count,b.count),a[prefix]==b[prefix] {prefix+=1}
            while suffix<min(a.count,b.count)-prefix,a[a.count-1-suffix]==b[b.count-1-suffix] {suffix+=1}
            guard prefix+suffix>0 else {throw tooLarge()}
            var parts=[Part]()
            if prefix>0 {parts.append(.init(offset:0,count:prefix,literal:nil))}
            let literal=Data(a[prefix..<(a.count-suffix)])
            if !literal.isEmpty {parts.append(.init(offset:nil,count:literal.count,literal:literal))}
            if suffix>0 {parts.append(.init(offset:UInt64(b.count-suffix),count:suffix,literal:nil))}
            guard try reader.fingerprint(at:original)==before,try reader.fingerprint(at:output)==after else {throw RestoreError(.conflict,"Compact inputs changed during capture.")}
            return .init(parts:parts)
        }
        let limit=min(16*1024*1024,max(128*1024,Int(before.snapshot.id.size/8)))
        var index=[Data:(UInt64,Int)](),parts=[Part](),literalCount=0
        try chunks(output) {offset,data in
            guard index.count<1_000_000 else {throw tooLarge()}
            index[Data(SHA256.hash(data:data))]=(offset,data.count)
        }
        try chunks(original) {_,data in
            if let match=index[Data(SHA256.hash(data:data))],match.1==data.count {parts.append(.init(offset:match.0,count:data.count,literal:nil))}
            else {literalCount+=data.count;guard literalCount<=limit else {throw tooLarge()};parts.append(.init(offset:nil,count:data.count,literal:data))}
        }
        guard literalCount<Int(before.snapshot.id.size),try reader.fingerprint(at:original)==before,try reader.fingerprint(at:output)==after else {throw tooLarge()}
        let delta=ReverseDelta(parts:parts)
        guard try JSONEncoder().encode(delta).count<=maximumPayload else {throw tooLarge()}
        return delta
    }
    static func tooLarge()->RestoreError {.init(.unsupported,"Metadata backup cannot represent this change within its compact limit (16 MiB of original fragments, 24 MiB encoded). Choose Full backup and preview again.")}
    private static func chunks(_ url:URL,_ visit:(UInt64,Data)throws->Void) throws {
        let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open compact delta input")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? handle.close()}
        var chunk=Data(),offset:UInt64=0,rolling:UInt64=0
        while let data=try handle.read(upToCount:1_048_576),!data.isEmpty {
            try Task.checkCancellation()
            for byte in data {
                // Multiplication mixes the byte; 64 shifts forget prior bytes so an
                // inserted header converges on the same content boundaries.
                rolling=(rolling &<< 1) &+ (UInt64(byte) &* 0x9e3779b97f4a7c15)
                chunk.append(byte)
                if chunk.count>=2048 && (rolling & 8191==0 || chunk.count>=65536) {
                    try visit(offset,chunk);offset+=UInt64(chunk.count);chunk.removeAll(keepingCapacity:true)
                }
            }
        }
        if !chunk.isEmpty {try visit(offset,chunk)}
    }
    func restore(output:URL,to target:URL) throws {
        let input=open(output.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC),destination=open(target.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard input>=0,destination>=0 else {if input>=0 {close(input)};if destination>=0 {close(destination)};throw SecureFS.error("Open compact reconstruction")}
        let source=FileHandle(fileDescriptor:input,closeOnDealloc:true),sink=FileHandle(fileDescriptor:destination,closeOnDealloc:true)
        defer {try? source.close();try? sink.close()}
        for part in parts {
            guard part.count>=0 else {throw RestoreError(.invalidInput,"Invalid compact fragment.")}
            if let literal=part.literal {guard literal.count==part.count,part.offset==nil else {throw RestoreError(.invalidInput,"Invalid compact literal.")};try sink.write(contentsOf:literal)}
            else if let offset=part.offset {
                try source.seek(toOffset:offset);var remaining=part.count
                while remaining>0 {try Task.checkCancellation();let bytes=try source.read(upToCount:min(remaining,1_048_576)) ?? Data();guard !bytes.isEmpty else {throw RestoreError(.conflict,"Compact undo payload is missing or truncated.")};try sink.write(contentsOf:bytes);remaining-=bytes.count}
            } else {throw RestoreError(.invalidInput,"Invalid compact reference.")}
        }
        try sink.synchronize()
    }
}
