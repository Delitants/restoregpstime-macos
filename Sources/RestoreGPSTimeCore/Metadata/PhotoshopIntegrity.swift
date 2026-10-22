import Foundation

// Photoshop image resource blocks: only IPTC, XMP, their digest and the legacy caption are descriptive.
struct PhotoshopIntegrity {
    func protect(_ reader:BoundedMediaReader,offset:UInt64,length:UInt64,digest:inout MediaDigest) throws {
        let header=Data("Photoshop 3.0\0".utf8)
        guard length>=UInt64(header.count),try reader.bytes(offset,header.count)==header else {try digest.range(reader,offset,length,label:"opaque-APP13",pixels:false);return}
        let end=offset+length;var at=offset+UInt64(header.count),count=0
        let descriptive:Set<UInt64>=[0x03f0,0x0404,0x0424,0x0425]
        while at<end {
            count+=1;guard count<=4096,end-at>=7,try reader.bytes(at,4)==Data("8BIM".utf8) else {throw RestoreError(.unsupported,"Unqualified Photoshop resource block layout.")}
            let start=at,id=try reader.integer(at+4,width:2),nameLength=try reader.integer(at+6,width:1)
            let nameBytes=1+nameLength,paddedName=nameBytes+(nameBytes&1)
            at+=6+paddedName
            guard at<=end,end-at>=4 else {throw RestoreError(.malformedMetadata,"Truncated Photoshop resource name.")}
            let size=try reader.integer(at,width:4);at+=4
            guard size<=end-at,size+(size&1)<=end-at else {throw RestoreError(.malformedMetadata,"Photoshop resource extent exceeds APP13.")}
            at+=size+(size&1)
            if !descriptive.contains(id) {try digest.range(reader,start,at-start,label:"Photoshop-\(id)",pixels:id==0x0409 || id==0x040c)}
        }
    }
}
