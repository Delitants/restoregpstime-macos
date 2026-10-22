import Foundation
import CryptoKit

/// Inspect local references before AVFoundation can resolve a URL or file alias.
/// Preserve handler bytes by track and container role, rather than comparing
/// independently flattened ExifTool fields whose Copy numbers may change.
struct VideoContainerPreflight {
    func signature(at url:URL) throws -> String {
        let reader=try BoundedMediaReader(url)
        func children(_ box:ISOBox) throws -> [ISOBox] {
            try Task.checkCancellation()
            let result=try ISOBoxes.read(reader,start:box.content,end:box.end)
            guard !result.contains(where:{["cmov","rmra","rmda","rdrf"].contains($0.type)}) else {
                throw RestoreError(.unsupported,"Compressed and reference movies are not qualified for offline processing.")
            }
            return result
        }
        let root=try ISOBoxes.read(reader,start:0,end:reader.size)
        for box in root {
            if box.type=="uuid",box.length>=16,try reader.bytes(box.content,16).hex=="be7acfcb97a942e89c71999491e3afac" {continue} // Adobe XMP; verified by the metadata diff.
            guard ["ftyp","moov","mdat","free","skip","wide"].contains(box.type) else {
                throw RestoreError(.unsupported,"The video has an unqualified top-level container layout.")
            }
        }
        let movie=try children(ISOBoxes.one(root,"moov")),tracks=movie.filter {$0.type=="trak"}
        guard !tracks.isEmpty,tracks.count<=64 else {throw RestoreError(.unsupported,"Video track count is outside the qualified profile.")}
        var byID=[UInt64:String]()
        for track in tracks {
            let boxes=try children(track),header=try ISOBoxes.one(boxes,"tkhd")
            guard header.length>=4 else {throw RestoreError(.malformedMetadata,"Truncated video track header.")}
            let version=try reader.integer(header.content,width:1),offset:UInt64
            switch version {case 0:offset=12;case 1:offset=20;default:throw RestoreError(.unsupported,"Unqualified video track header version.")}
            guard header.length>=offset+4 else {throw RestoreError(.malformedMetadata,"Truncated video track identity.")}
            let id=try reader.integer(header.content+offset,width:4)
            guard id != 0,byID[id]==nil else {throw RestoreError(.malformedMetadata,"Invalid or duplicate video track identity.")}
            let media=try children(ISOBoxes.one(boxes,"mdia")),information=try children(ISOBoxes.one(media,"minf"))
            var hash=SHA256()
            for (role,handlers) in [("media",media.filter {$0.type=="hdlr"}),("data",information.filter {$0.type=="hdlr"})] {
                guard (role != "media" || handlers.count==1),handlers.count<=1 else {throw RestoreError(.unsupported,"Unqualified video handler layout.")}
                hash.field(role);hash.field(UInt64(handlers.count))
                for handler in handlers {hash.field(handler.length);try reader.feed(handler.content,handler.length,into:&hash)}
            }
            let dataInfo=try children(ISOBoxes.one(information,"dinf")),reference=try ISOBoxes.one(dataInfo,"dref")
            guard reference.length>=8,try reader.integer(reference.content,width:4)==0 else {throw RestoreError(.malformedMetadata,"Unqualified video data reference header.")}
            let count=try reader.integer(reference.content+4,width:4),entries=try ISOBoxes.read(reader,start:reference.content+8,end:reference.end)
            guard count>0,count<=128,count==entries.count else {throw RestoreError(.malformedMetadata,"Invalid video data reference count.")}
            for entry in entries {
                guard ["url ","alis"].contains(entry.type),entry.length==4,try reader.integer(entry.content,width:4)==1 else {
                    throw RestoreError(.unsupported,"External, alias and non-self-contained media references are not allowed during offline processing.")
                }
                hash.field(entry.type);try reader.feed(entry.content,entry.length,into:&hash)
            }
            let table=try children(ISOBoxes.one(information,"stbl")),descriptions=try ISOBoxes.one(table,"stsd")
            guard descriptions.length>=8,try reader.integer(descriptions.content,width:4)==0 else {throw RestoreError(.malformedMetadata,"Invalid video sample description header.")}
            let sampleCount=try reader.integer(descriptions.content+4,width:4),samples=try ISOBoxes.read(reader,start:descriptions.content+8,end:descriptions.end)
            guard sampleCount>0,sampleCount<=128,sampleCount==samples.count else {throw RestoreError(.malformedMetadata,"Invalid video sample description count.")}
            for sample in samples {
                guard !["encv","enca","drmi","drms"].contains(sample.type),sample.length>=8 else {throw RestoreError(.unsupported,"Encrypted or truncated video sample descriptions are not qualified.")}
                let index=try reader.integer(sample.content+6,width:2)
                guard index>0,index<=count else {throw RestoreError(.malformedMetadata,"A video sample references unavailable media data.")}
                hash.field(sample.type);hash.field(index)
            }
            byID[id]=hash.finalize().hex
        }
        var result=SHA256();result.field("local-video-references-and-handlers-v1")
        for id in byID.keys.sorted() {result.field(id);result.field(byID[id]!)}
        return result.finalize().hex
    }
}
