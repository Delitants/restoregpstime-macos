import Foundation
import CryptoKit

// TIFF 6.0 / BigTIFF: bounded IFD graph and image-bearing strips, tiles and JPEG extents.
struct TIFFIntegrity {
    func signature(_ reader:BoundedMediaReader,base:UInt64=0,length:UInt64?=nil,metadataOnly:Bool=false) throws -> MediaIntegritySignature {
        let limit=length ?? reader.size
        try reader.checked(base,limit)
        func check(_ at:UInt64,_ count:UInt64) throws {guard at<=limit,count<=limit-at else {throw RestoreError(.malformedMetadata,"A TIFF field/extent is outside its container.")}}
        func bytes(_ at:UInt64,_ count:Int) throws -> Data {try check(at,UInt64(count));return try reader.bytes(base+at,count)}
        let order=try bytes(0,2),little:Bool
        if order==Data([0x49,0x49]) {little=true} else if order==Data([0x4d,0x4d]) {little=false} else {throw RestoreError(.malformedMetadata,"Invalid TIFF byte order.")}
        func uint(_ at:UInt64,_ width:Int) throws -> UInt64 {try check(at,UInt64(width));return try reader.integer(base+at,width:width,little:little)}
        let magic=try uint(2,2),big=magic==43
        guard magic==42 || big else {throw RestoreError(.malformedMetadata,"Invalid TIFF magic.")}
        if big {guard try uint(4,2)==8,(try uint(6,2))==0 else {throw RestoreError(.unsupported,"Unsupported BigTIFF offset layout.")}}
        let countWidth=big ? 8:2,entryWidth=big ? 20:12,offsetWidth=big ? 8:4,headerLength=UInt64(big ? 16:8)
        let first=try uint(big ? 8:4,offsetWidth)
        var digest=MediaDigest(),visited=Set<UInt64>(),coverage=[(UInt64,UInt64)](),imageExtents=0,ifdCount=0,totalFields:UInt64=0,protectedFields=0
        coverage.append((0,headerLength))
        let typeWidths:[UInt64:UInt64]=[1:1,2:1,3:2,4:4,5:8,6:1,7:1,8:2,9:4,10:8,11:4,12:8,13:4,16:8,17:8,18:8]
        let storage:Set<UInt64>=[273,279,324,325,513,514]
        let rendering:Set<UInt64>=[254,255,256,257,258,259,262,263,264,265,266,274,277,278,280,281,282,283,284,286,287,290,291,292,293,296,297,301,317,318,319,320,321,322,323,332,333,334,336,337,338,339,340,341,342,343,344,34377,34675,529,530,531,532,32997,32998]
        let descriptive:Set<UInt64>=[269,270,271,272,285,288,289,305,306,315,316,700,33723,34377,33432,34665,34853]
        let exifRendering:Set<UInt64>=[0x927c,0xa001,0xa002,0xa003,0xa500]
        struct Field {let type:UInt64,count:UInt64,at:UInt64,bytes:UInt64,width:UInt64}
        func values(_ field:Field) throws -> [UInt64] {
            guard [UInt64(1),3,4,13,16,18].contains(field.type),field.count<=100000 else {throw RestoreError(.unsupported,"Unsupported TIFF offset/count representation.")}
            return try (0..<field.count).map {try uint(field.at+$0*field.width,Int(field.width))}
        }
        func walk(_ start:UInt64,path:String,context:String,depth:Int) throws {
            if start==0 {return}
            guard depth<=32,visited.insert(start).inserted,ifdCount<1024 else {throw RestoreError(.malformedMetadata,"TIFF IFD cycle or traversal bound exceeded.")};ifdCount+=1
            let count=try uint(start,countWidth)
            totalFields+=count
            guard count<=65536,totalFields<=100000 else {throw RestoreError(.unsupported,"TIFF IFD field count exceeds its bound.")}
            let tableBytes=UInt64(countWidth)+count*UInt64(entryWidth)+UInt64(offsetWidth)
            try check(start,tableBytes);coverage.append((start,tableBytes))
            var fields=[UInt64:Field]()
            for index in 0..<count {
                let at=start+UInt64(countWidth)+index*UInt64(entryWidth),tag=try uint(at,2),type=try uint(at+2,2),items=try uint(at+4,big ? 8:4)
                guard fields[tag]==nil,let width=typeWidths[type] else {throw RestoreError(.unsupported,"Unknown or duplicate TIFF field layout.")}
                let total=items.multipliedReportingOverflow(by:width)
                guard !total.overflow,total.partialValue<=16_777_216 else {throw RestoreError(.unsupported,"TIFF field size exceeds its bounded profile.")}
                let inline=at+UInt64(big ? 12:8),valueAt=try total.partialValue<=UInt64(offsetWidth) ? inline:uint(inline,offsetWidth)
                try check(valueAt,total.partialValue);coverage.append((valueAt,total.partialValue))
                fields[tag]=Field(type:type,count:items,at:valueAt,bytes:total.partialValue,width:width)
                let protect=context=="interop" || (context=="exif" ? exifRendering.contains(tag):rendering.contains(tag))
                if protect {
                    protectedFields+=1
                    if [UInt64(1),3,4,13,16,18].contains(type) {
                        digest.field("\(path):\(tag):unsigned:\(items)")
                        for number in try values(fields[tag]!) {digest.field(String(number))}
                    } else if type==5 {
                        guard items<=100000 else {throw RestoreError(.unsupported,"TIFF rational array exceeds its bound.")}
                        digest.field("\(path):\(tag):rational:\(items)")
                        for index in 0..<items {
                            let numerator=try uint(valueAt+index*8,4),denominator=try uint(valueAt+index*8+4,4)
                            guard denominator>0 else {throw RestoreError(.malformedMetadata,"A TIFF rendering rational has a zero denominator.")}
                            var a=numerator,b=denominator
                            while b != 0 {let next=a%b;a=b;b=next}
                            digest.field("\(numerator/a)/\(denominator/a)")
                        }
                    } else {digest.field("\(path):\(tag):\(type):\(items)");try digest.range(reader,base+valueAt,total.partialValue,label:"field",pixels:false)}
                }
                else if context=="image" && !descriptive.contains(tag) && !storage.contains(tag) && tag != 330 {throw RestoreError(.unsupported,"Unqualified TIFF rendering/private field: \(tag).")}
            }
            for (offsetTag,countTag) in [(UInt64(273),UInt64(279)),(324,325),(513,514)] {
                if fields[offsetTag] != nil || fields[countTag] != nil {
                    guard let offsets=fields[offsetTag],let counts=fields[countTag] else {throw RestoreError(.malformedMetadata,"A TIFF image extent has no matching offset/count table.")}
                    let starts=try values(offsets),lengths=try values(counts)
                    guard starts.count==lengths.count,!starts.isEmpty else {throw RestoreError(.malformedMetadata,"Mismatched TIFF image extent tables.")}
                    for (index,pair) in zip(starts,lengths).enumerated() {
                        guard pair.1>0 else {throw RestoreError(.malformedMetadata,"An empty TIFF image extent cannot be verified.")}
                        try check(pair.0,pair.1);coverage.append((pair.0,pair.1));imageExtents+=1
                        guard imageExtents<=100000 else {throw RestoreError(.unsupported,"TIFF image extent count exceeds its bound.")}
                        try digest.range(reader,base+pair.0,pair.1,label:"\(path):\(offsetTag):\(index)",pixels:true)
                    }
                }
            }
            for (tag,label,targetContext) in [(UInt64(330),"sub","image"),(34665,"exif","exif"),(34853,"gps","gps"),(40965,"interop","interop")] {
                if let field=fields[tag] {for (index,offset) in try values(field).enumerated() {try walk(offset,path:path+"/\(label)\(index)",context:targetContext,depth:depth+1)}}
            }
            let next=try uint(start+UInt64(countWidth)+count*UInt64(entryWidth),offsetWidth)
            if next != 0 {try walk(next,path:path+"/next",context:context,depth:depth+1)}
        }
        try walk(first,path:"ifd0",context:"image",depth:0)
        guard metadataOnly || imageExtents>0 else {throw RestoreError(.unsupported,"No understood TIFF image-bearing extents were found.")}
        // Nonzero unreferenced storage may be an unsupported preview/auxiliary image.
        let ranges=coverage.sorted {$0.0<$1.0};var end:UInt64=0
        for (offset,count) in ranges+[(limit,0)] {
            if offset>end {
                var cursor=end
                while cursor<offset {let n=Int(min(offset-cursor,1_048_576));if try bytes(cursor,n).contains(where:{$0 != 0}) {throw RestoreError(.unsupported,"Unreferenced TIFF storage requires a model-specific integrity profile.")};cursor+=UInt64(n)}
            }
            end=max(end,offset+count)
        }
        if !metadataOnly || protectedFields>0 || imageExtents>0 {digest.field(little ? "little-endian":"big-endian")}
        return digest.signature(profile:metadataOnly ? "EXIF-TIFF":"TIFF",validator:"tiff-extents-v1")
    }
}
