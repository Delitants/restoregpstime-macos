import Foundation

// ITU-T T.81 marker/entropy framing; metadata APP1/APP13/COM is checked separately.
struct JPEGIntegrity {
    func signature(_ reader:BoundedMediaReader) throws -> MediaIntegritySignature {
        guard try reader.bytes(0,2)==Data([0xff,0xd8]) else {throw RestoreError(.malformedMetadata,"Invalid JPEG SOI.")}
        var cursor=MediaCursor(reader),digest=MediaDigest(),scans=0,frames=0,segments=0
        try cursor.seek(2)
        while cursor.position<reader.size {
            segments+=1;guard segments<=65536 else {throw RestoreError(.unsupported,"JPEG marker count exceeds the parser bound.")}
            let markerStart=cursor.position
            guard try cursor.byte()==0xff else {throw RestoreError(.malformedMetadata,"Invalid JPEG marker boundary.")}
            var marker=try cursor.byte();while marker==0xff {marker=try cursor.byte()}
            if marker==0xd9 {
                guard scans>0,frames>0,cursor.position==reader.size else {throw RestoreError(.unsupported,"JPEG trailers or multiple-image layouts require a separately qualified profile.")}
                digest.field("EOI");return digest.signature(profile:"JPEG",validator:"jpeg-scans-v1")
            }
            guard marker != 0x00,marker != 0xd8,!(0xd0...0xd7).contains(marker),marker != 0x01 else {throw RestoreError(.unsupported,"Unsupported standalone JPEG marker.")}
            let length=try reader.integer(cursor.position,width:2)
            guard length>=2 else {throw RestoreError(.malformedMetadata,"Invalid JPEG segment length.")}
            let dataStart=cursor.position+2,dataLength=length-2,end=cursor.position+length
            try reader.checked(dataStart,dataLength)
            if marker==0xe2,dataLength>=4,try reader.bytes(dataStart,4)==Data([0x4d,0x50,0x46,0]) {throw RestoreError(.unsupported,"Multi-picture JPEG requires qualified auxiliary-image preservation.")}
            if (0xc0...0xcf).contains(marker) && ![UInt8(0xc4),0xc8,0xcc].contains(marker) {frames+=1}
            if marker==0xe1,dataLength>=6,try reader.bytes(dataStart,6)==Data("Exif\0\0".utf8) {
                let embedded=try TIFFIntegrity().signature(reader,base:dataStart+6,length:dataLength-6,metadataOnly:true)
                let empty=FileIdentityReader.hash(Data())
                if embedded.payloadHash != empty || embedded.structureHash != empty {digest.field("Exif:"+embedded.payloadHash+":"+embedded.structureHash)}
            }
            if marker==0xed {try PhotoshopIntegrity().protect(reader,offset:dataStart,length:dataLength,digest:&digest)}
            if marker != 0xe1 && marker != 0xed && marker != 0xfe {try digest.range(reader,markerStart,end-markerStart,label:"marker-\(marker)",pixels:false)}
            try cursor.seek(end)
            if marker==0xda {
                scans+=1;let scanStart=cursor.position;var finished=false
                while cursor.position<reader.size {
                    if try cursor.byte() != 0xff {continue}
                    let possibleEnd=cursor.position-1;var next=try cursor.byte()
                    while next==0xff {next=try cursor.byte()}
                    if next==0 || (0xd0...0xd7).contains(next) {continue}
                    try digest.range(reader,scanStart,possibleEnd-scanStart,label:"scan-\(scans)",pixels:true)
                    try cursor.seek(possibleEnd);finished=true;break
                }
                guard finished else {throw RestoreError(.malformedMetadata,"JPEG entropy data has no terminating marker.")}
            }
        }
        throw RestoreError(.malformedMetadata,"JPEG EOI is missing.")
    }
}
