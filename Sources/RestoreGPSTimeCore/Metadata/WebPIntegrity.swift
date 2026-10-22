import Foundation

// https://developers.google.com/speed/webp/docs/riff_container
struct WebPIntegrity {
    struct Chunk {let type:String,offset:UInt64,length:UInt64}
    func signature(_ reader:BoundedMediaReader) throws -> MediaIntegritySignature {
        guard try reader.bytes(0,4)==Data("RIFF".utf8),try reader.bytes(8,4)==Data("WEBP".utf8),try reader.integer(4,width:4,little:true)+8==reader.size else {throw RestoreError(.malformedMetadata,"Invalid WebP RIFF extent.")}
        let chunks=try parse(reader,start:12,end:reader.size)
        let known:Set<String>=["VP8X","VP8 ","VP8L","ALPH","ICCP","ANIM","ANMF","EXIF","XMP "]
        guard chunks.allSatisfy({known.contains($0.type)}) else {throw RestoreError(.unsupported,"Unknown WebP chunks require additional integrity qualification.")}
        for singleton in ["VP8X","ICCP","ANIM","EXIF","XMP ","ALPH"] {guard chunks.filter({$0.type==singleton}).count<=1 else {throw RestoreError(.malformedMetadata,"Duplicate WebP singleton chunk.")}}
        var digest=MediaDigest(),canvas:(UInt64,UInt64)?,flags:UInt64?,alpha=false,imageCount=0,animationCount=0
        if let extended=chunks.first(where:{$0.type=="VP8X"}) {
            guard extended.length==10,try reader.integer(extended.offset+1,width:3)==0 else {throw RestoreError(.malformedMetadata,"Invalid WebP extended header.")}
            let bits=try reader.integer(extended.offset,width:1)
            guard bits & 0xc1==0 else {throw RestoreError(.unsupported,"Unqualified WebP extended feature bits.")}
            flags=bits;canvas=(try reader.integer(extended.offset+4,width:3,little:true)+1,try reader.integer(extended.offset+7,width:3,little:true)+1)
        }
        for chunk in chunks {
            switch chunk.type {
            case "VP8 ","VP8L":
                let dimensions=try image(reader,chunk)
                if canvas==nil {canvas=(dimensions.0,dimensions.1)}
                guard let canvas,canvas.0==dimensions.0,canvas.1==dimensions.1 else {throw RestoreError(.unsupported,"A still WebP frame differs from its canvas.")}
                alpha=alpha || dimensions.2;imageCount+=1
                try digest.range(reader,chunk.offset,chunk.length,label:chunk.type,pixels:true)
            case "ALPH":alpha=true;try digest.range(reader,chunk.offset,chunk.length,label:"alpha",pixels:true)
            case "ANIM":guard chunk.length==6 else {throw RestoreError(.malformedMetadata,"Invalid WebP animation header.")};try digest.range(reader,chunk.offset,chunk.length,label:"animation",pixels:false)
            case "ANMF":
                guard chunk.length>=16,let canvas else {throw RestoreError(.malformedMetadata,"WebP animation requires a canvas and frame header.")}
                let x=try reader.integer(chunk.offset,width:3,little:true)*2,y=try reader.integer(chunk.offset+3,width:3,little:true)*2
                let w=try reader.integer(chunk.offset+6,width:3,little:true)+1,h=try reader.integer(chunk.offset+9,width:3,little:true)+1,frameFlags=try reader.integer(chunk.offset+15,width:1)
                guard x<=canvas.0,y<=canvas.1,w<=canvas.0-x,h<=canvas.1-y,frameFlags & ~3==0 else {throw RestoreError(.malformedMetadata,"Invalid WebP animation frame extent/flags.")}
                let frame=try parse(reader,start:chunk.offset+16,end:chunk.offset+chunk.length)
                guard frame.allSatisfy({["ALPH","VP8 ","VP8L"].contains($0.type)}),frame.filter({$0.type=="VP8 " || $0.type=="VP8L"}).count==1 else {throw RestoreError(.unsupported,"Unqualified WebP animation subchunk layout.")}
                for part in frame {
                    if part.type=="ALPH" {alpha=true}
                    else {let dim=try image(reader,part);guard dim.0==w,dim.1==h else {throw RestoreError(.malformedMetadata,"WebP frame dimensions do not agree.")};alpha=alpha || dim.2}
                }
                animationCount+=1;try digest.range(reader,chunk.offset,chunk.length,label:"animated-frame",pixels:true)
            case "ICCP":try digest.range(reader,chunk.offset,chunk.length,label:"ICC",pixels:false)
            case "EXIF":
                let prefixed=try chunk.length>=6 && reader.bytes(chunk.offset,6)==Data("Exif\0\0".utf8)
                let skip:UInt64=prefixed ? 6:0
                let result=try TIFFIntegrity().signature(reader,base:chunk.offset+skip,length:chunk.length-skip,metadataOnly:true),empty=FileIdentityReader.hash(Data())
                if result.payloadHash != empty || result.structureHash != empty {digest.field("Exif:"+result.payloadHash+":"+result.structureHash)}
            default:break
            }
        }
        guard let canvas,(imageCount==1 && animationCount==0) || (imageCount==0 && animationCount>0) else {throw RestoreError(.unsupported,"WebP has no unique understood still/animated image layout.")}
        let animated=animationCount>0,hasICC=chunks.contains(where:{$0.type=="ICCP"})
        guard chunks.contains(where:{$0.type=="ANIM"})==animated else {throw RestoreError(.malformedMetadata,"WebP animation flags/header do not agree.")}
        let features:UInt64=(alpha ? 16:0)|(animated ? 2:0)|(hasICC ? 32:0)
        if let flags {
            let metadata:UInt64=(chunks.contains(where:{$0.type=="EXIF"}) ? 8:0)|(chunks.contains(where:{$0.type=="XMP "}) ? 4:0)
            guard flags==features|metadata else {throw RestoreError(.malformedMetadata,"WebP extended flags do not agree with stored chunks.")}
        } else if animated || hasICC || chunks.contains(where:{$0.type=="EXIF" || $0.type=="XMP "}) {throw RestoreError(.malformedMetadata,"Extended WebP chunks require VP8X.")}
        digest.field("canvas:\(canvas.0)x\(canvas.1):\(features)")
        return digest.signature(profile:"WEBP",validator:"webp-chunks-v1")
    }
    private func parse(_ reader:BoundedMediaReader,start:UInt64,end:UInt64) throws -> [Chunk] {
        var at=start,result=[Chunk]()
        guard end<=reader.size else {throw RestoreError(.malformedMetadata,"WebP chunk parent exceeds the file.")}
        while at<end {
            guard end-at>=8,result.count<100000 else {throw RestoreError(.malformedMetadata,"Truncated or excessive WebP chunk sequence.")}
            let type=String(decoding:try reader.bytes(at,4),as:UTF8.self),size=try reader.integer(at+4,width:4,little:true)
            guard size<=end-at-8,size+(size&1)<=end-at-8 else {throw RestoreError(.malformedMetadata,"A WebP chunk exceeds its parent.")}
            if size&1==1,try reader.integer(at+8+size,width:1) != 0 {throw RestoreError(.malformedMetadata,"Invalid WebP padding byte.")}
            result.append(.init(type:type,offset:at+8,length:size));at+=8+size+(size&1)
        }
        return result
    }
    private func image(_ reader:BoundedMediaReader,_ chunk:Chunk) throws -> (UInt64,UInt64,Bool) {
        if chunk.type=="VP8 " {
            guard chunk.length>=10,try reader.bytes(chunk.offset+3,3)==Data([0x9d,0x01,0x2a]) else {throw RestoreError(.unsupported,"Unqualified WebP VP8 frame header.")}
            let w=try reader.integer(chunk.offset+6,width:2,little:true)&0x3fff,h=try reader.integer(chunk.offset+8,width:2,little:true)&0x3fff
            guard w>0,h>0 else {throw RestoreError(.malformedMetadata,"Invalid WebP VP8 dimensions.")};return (w,h,false)
        }
        guard chunk.length>=5,try reader.integer(chunk.offset,width:1)==0x2f else {throw RestoreError(.malformedMetadata,"Invalid WebP lossless signature.")}
        let info=try reader.integer(chunk.offset+1,width:4,little:true)
        guard info>>29==0 else {throw RestoreError(.unsupported,"Unqualified WebP lossless version.")}
        return ((info&0x3fff)+1,((info>>14)&0x3fff)+1,(info>>28)&1==1)
    }
}
