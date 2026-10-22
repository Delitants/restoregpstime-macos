import Foundation
import Darwin
import CryptoKit

final class BoundedMediaReader {
    let handle:FileHandle
    let size:UInt64
    init(_ url:URL) throws {
        let snapshot=try FileIdentityReader().snapshot(at:url)
        guard snapshot.kind == .regular else {throw RestoreError(.unsupported,"Integrity verification requires an available ordinary file.")}
        let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw SecureFS.error("Open media for integrity verification")}
        handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);size=snapshot.id.size
        var st=stat()
        guard fstat(fd,&st)==0,UInt64(st.st_ino)==snapshot.id.inode,UInt64(UInt32(bitPattern:st.st_dev))==snapshot.id.device else {try? handle.close();throw RestoreError(.conflict,"Media changed while opening it.")}
    }
    deinit {try? handle.close()}
    func checked(_ offset:UInt64,_ length:UInt64) throws {
        guard offset<=size,length<=size-offset else {throw RestoreError(.malformedMetadata,"A media extent is outside its file.")}
    }
    func bytes(_ offset:UInt64,_ count:Int) throws -> Data {
        guard count>=0,count<=1_048_576 else {throw RestoreError(.unsupported,"The media parser exceeded its bounded read size.")}
        try Task.checkCancellation();try checked(offset,UInt64(count));try handle.seek(toOffset:offset)
        let data=try handle.read(upToCount:count) ?? Data()
        guard data.count==count else {throw RestoreError(.malformedMetadata,"A media extent was truncated.")};return data
    }
    func integer(_ offset:UInt64,width:Int,little:Bool=false) throws -> UInt64 {
        guard [0,1,2,3,4,8].contains(width) else {throw RestoreError(.unsupported,"Unsupported media integer width.")}
        let data=try bytes(offset,width)
        let ordered=little ? Array(data.reversed()):Array(data)
        return ordered.reduce(UInt64(0)) {($0<<8)|UInt64($1)}
    }
    func feed(_ offset:UInt64,_ length:UInt64,into hash:inout SHA256) throws {
        try checked(offset,length);var at=offset,remaining=length
        while remaining>0 {try Task.checkCancellation();let count=Int(min(remaining,1_048_576));hash.update(data:try bytes(at,count));at+=UInt64(count);remaining-=UInt64(count)}
    }
    func hash(_ offset:UInt64,_ length:UInt64) throws -> String {var hash=SHA256();try feed(offset,length,into:&hash);return hash.finalize().hex}
}
extension Sequence where Element==UInt8 {var hex:String {map {String(format:"%02x",$0)}.joined()}}
extension SHA256 {
    mutating func field(_ value:String) {let data=Data(value.utf8);field(UInt64(data.count));update(data:data)}
    mutating func field(_ value:UInt64) {var big=value.bigEndian;withUnsafeBytes(of:&big) {update(bufferPointer:$0)}}
}
struct MediaDigest {
    var payload=SHA256(),structure=SHA256()
    mutating func range(_ reader:BoundedMediaReader,_ offset:UInt64,_ length:UInt64,label:String,pixels:Bool) throws {
        if pixels {payload.field(label);payload.field(length);try reader.feed(offset,length,into:&payload)}
        else {structure.field(label);structure.field(length);try reader.feed(offset,length,into:&structure)}
    }
    mutating func field(_ value:String) {structure.field(value)}
    func signature(profile:String,validator:String)->MediaIntegritySignature {.init(profile:profile,validator:validator,payloadHash:payload.finalize().hex,structureHash:structure.finalize().hex)}
}
struct MediaCursor {
    let reader:BoundedMediaReader
    var position:UInt64=0
    private var start:UInt64=0,buffer=Data()
    init(_ reader:BoundedMediaReader) {self.reader=reader}
    mutating func byte() throws -> UInt8 {
        guard position<reader.size else {throw RestoreError(.malformedMetadata,"Unexpected end of compressed media.")}
        if position<start || position-start>=UInt64(buffer.count) {start=position;buffer=try reader.bytes(position,Int(min(1_048_576,reader.size-position)))}
        let value=buffer[Int(position-start)];position+=1;return value
    }
    mutating func seek(_ offset:UInt64) throws {try reader.checked(offset,0);position=offset}
}
