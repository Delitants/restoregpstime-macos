import Foundation

// https://www.w3.org/TR/png-3/ — chunk framing, CRC and rendering/APNG chunks.
struct PNGIntegrity {
    static let crcTable:[UInt32]=(0..<256).map {value in (0..<8).reduce(UInt32(value)) {n,_ in n&1==1 ? 0xedb88320^(n>>1):n>>1}}
    func signature(_ reader:BoundedMediaReader) throws -> MediaIntegritySignature {
        guard try reader.bytes(0,8)==Data([137,80,78,71,13,10,26,10]) else {throw RestoreError(.malformedMetadata,"Invalid PNG signature.")}
        var at:UInt64=8,digest=MediaDigest(),chunks=0,hasHeader=false,hasData=false
        let descriptive:Set<String>=["eXIf","tEXt","zTXt","iTXt","tIME"]
        while at<reader.size {
            chunks+=1;guard chunks<=100000 else {throw RestoreError(.unsupported,"PNG chunk count exceeds the parser bound.")}
            let length=try reader.integer(at,width:4),typeData=try reader.bytes(at+4,4)
            guard typeData.allSatisfy({(65...90).contains($0)||(97...122).contains($0)}),typeData[2]&32==0 else {throw RestoreError(.malformedMetadata,"Invalid PNG chunk type.")}
            let type=String(decoding:typeData,as:UTF8.self);try reader.checked(at+8,length+4)
            if chunks==1 {guard type=="IHDR",length==13 else {throw RestoreError(.malformedMetadata,"PNG IHDR is missing.")};hasHeader=true}
            var crc:UInt32=0xffffffff,offset=at+4,remaining=length+4
            while remaining>0 {try Task.checkCancellation();let count=Int(min(remaining,1_048_576));for byte in try reader.bytes(offset,count) {crc=(crc>>8)^Self.crcTable[Int((crc^UInt32(byte))&255)]};offset+=UInt64(count);remaining-=UInt64(count)}
            guard UInt64(crc^0xffffffff)==(try reader.integer(at+8+length,width:4)) else {throw RestoreError(.malformedMetadata,"PNG chunk CRC mismatch.")}
            if type=="eXIf" {
                let embedded=try TIFFIntegrity().signature(reader,base:at+8,length:length,metadataOnly:true)
                let empty=FileIdentityReader.hash(Data())
                if embedded.payloadHash != empty || embedded.structureHash != empty {digest.field("Exif:"+embedded.payloadHash+":"+embedded.structureHash)}
            }
            if type=="IDAT" || type=="fdAT" {hasData=true;try digest.range(reader,at+8,length,label:type,pixels:true)}
            else if !descriptive.contains(type) {try digest.range(reader,at+4,length+4,label:type,pixels:false)}
            at+=length+12
            if type=="IEND" {guard length==0,hasHeader,hasData,at==reader.size else {throw RestoreError(.malformedMetadata,"Invalid PNG end/chunk layout.")};return digest.signature(profile:"PNG",validator:"png-chunks-v1")}
        }
        throw RestoreError(.malformedMetadata,"PNG IEND is missing.")
    }
}
