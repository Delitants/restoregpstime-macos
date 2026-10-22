import Foundation

struct ISOBox {
    let type:String,start:UInt64,size:UInt64,header:UInt64
    var content:UInt64 {start+header}
    var end:UInt64 {start+size}
    var length:UInt64 {size-header}
}
enum ISOBoxes {
    static func read(_ reader:BoundedMediaReader,start:UInt64,end:UInt64) throws -> [ISOBox] {
        guard start<=end,end<=reader.size else {throw RestoreError(.malformedMetadata,"Invalid ISO box parent extent.")}
        var at=start,result=[ISOBox]()
        while at<end {
            guard end-at>=8,result.count<10000 else {throw RestoreError(.malformedMetadata,"Truncated or excessive ISO box sequence.")}
            var size=try reader.integer(at,width:4),header:UInt64=8
            let type=String(decoding:try reader.bytes(at+4,4),as:UTF8.self)
            if size==1 {guard end-at>=16 else {throw RestoreError(.malformedMetadata,"Truncated extended ISO box header.")};size=try reader.integer(at+8,width:8);header=16}
            else if size==0 {size=end-at}
            guard size>=header,size<=end-at else {throw RestoreError(.malformedMetadata,"An ISO box exceeds its parent.")}
            result.append(.init(type:type,start:at,size:size,header:header));at+=size
        }
        return result
    }
    static func one(_ boxes:[ISOBox],_ type:String) throws -> ISOBox {
        let found=boxes.filter {$0.type==type}
        guard found.count==1,let box=found.first else {throw RestoreError(.unsupported,"The integrity profile requires exactly one \(type) box.")};return box
    }
}
struct HEIFIntegrity {
    let allowQualifiedAuxiliary:Bool
    let allowQualifiedHDR:Bool
    init(allowQualifiedAuxiliary:Bool=false,allowQualifiedHDR:Bool=false) {self.allowQualifiedAuxiliary=allowQualifiedAuxiliary;self.allowQualifiedHDR=allowQualifiedHDR}
    struct Info {let id:UInt64,type:String,box:ISOBox,metadata:Bool}
    struct Extent {let offset:UInt64,length:UInt64}
    func signature(_ reader:BoundedMediaReader,profile:String) throws -> MediaIntegritySignature {
        let root=try ISOBoxes.read(reader,start:0,end:reader.size),meta=try ISOBoxes.one(root,"meta"),ftyp=try ISOBoxes.one(root,"ftyp")
        guard root.allSatisfy({["ftyp","meta","mdat","free","skip","wide"].contains($0.type)}),meta.length>=4,try reader.integer(meta.content,width:4)==0 else {throw RestoreError(.unsupported,"Unqualified HEIF top-level/full-box layout.")}
        let children=try ISOBoxes.read(reader,start:meta.content+4,end:meta.end)
        guard children.allSatisfy({["hdlr","dinf","pitm","iinf","iref","iprp","iloc","idat","free"].contains($0.type)}) else {throw RestoreError(.unsupported,"Unqualified HEIF metadata box layout.")}
        var digest=MediaDigest()
        try digest.range(reader,ftyp.content,ftyp.length,label:"brands",pixels:false)
        for box in children where ["hdlr","dinf"].contains(box.type) {try digest.range(reader,box.content,box.length,label:box.type,pixels:false)}
        let pitm=try ISOBoxes.one(children,"pitm"),pv=try version(reader,pitm,allowed:[0,1])
        let primary=try integer(reader,pitm,pitm.content+4,pv==0 ? 2:4)
        digest.field("primary:\(primary)")
        let iinf=try ISOBoxes.one(children,"iinf"),iv=try version(reader,iinf,allowed:[0,1]),countWidth=iv==0 ? 2:4
        let infoCount=try integer(reader,iinf,iinf.content+4,countWidth),infoBoxes=try ISOBoxes.read(reader,start:iinf.content+4+UInt64(countWidth),end:iinf.end)
        guard infoCount==infoBoxes.count,infoCount<=10000,infoBoxes.allSatisfy({$0.type=="infe"}) else {throw RestoreError(.malformedMetadata,"Invalid HEIF item-info count.")}
        var infos=[UInt64:Info]()
        for box in infoBoxes {
            let version=try self.version(reader,box,allowed:[2,3],allowFlags:true),width=version==2 ? 2:4
            let id=try integer(reader,box,box.content+4,width),protection=try integer(reader,box,box.content+4+UInt64(width),2),typeAt=box.content+6+UInt64(width)
            guard protection==0,infos[id]==nil else {throw RestoreError(.unsupported,"Encrypted or duplicate HEIF items are not writable.")}
            let type=String(decoding:try bytes(reader,box,typeAt,4),as:UTF8.self)
            var stringAt=typeAt+4;_ = try zstring(reader,box,&stringAt)
            var metadata=type=="Exif"
            if type=="mime" {let contentType=try zstring(reader,box,&stringAt);let encoding=stringAt<box.end ? try zstring(reader,box,&stringAt):"";metadata=contentType=="application/rdf+xml" && encoding.isEmpty}
            guard metadata || ["hvc1","hev1","av01","jpeg","grid","iden","iovl"].contains(type) else {throw RestoreError(.unsupported,"Unqualified HEIF item type: \(type).")}
            infos[id] = .init(id:id,type:type,box:box,metadata:metadata)
            if !metadata {try digest.range(reader,box.content,box.length,label:"item-info:\(id)",pixels:false)}
        }
        guard let primaryInfo=infos[primary],!primaryInfo.metadata else {throw RestoreError(.malformedMetadata,"The HEIF primary image is missing.")}
        let metadataIDs=Set(infos.values.filter(\.metadata).map(\.id))
        let idats=children.filter {$0.type=="idat"},mdats=root.filter {$0.type=="mdat"}
        guard idats.count<=1,mdats.count<=1024 else {throw RestoreError(.unsupported,"Unqualified HEIF data-container layout.")}
        let iloc=try ISOBoxes.one(children,"iloc"),lv=try version(reader,iloc,allowed:[0,1,2])
        var at=iloc.content+4
        let sizes=try integer(reader,iloc,at,1),bases=try integer(reader,iloc,at+1,1);at+=2
        let offsetSize=Int(sizes>>4),lengthSize=Int(sizes&15),baseSize=Int(bases>>4),indexSize=lv==0 ? 0:Int(bases&15)
        guard [offsetSize,lengthSize,baseSize,indexSize].allSatisfy({[0,4,8].contains($0)}) else {throw RestoreError(.unsupported,"Unqualified HEIF extent integer widths.")}
        let itemCount=try integer(reader,iloc,at,lv<2 ? 2:4);at+=UInt64(lv<2 ? 2:4)
        guard itemCount<=10000 else {throw RestoreError(.unsupported,"HEIF item count exceeds its bound.")}
        var extents=[UInt64:[Extent]](),coverage=[Extent](),totalExtents=0
        for _ in 0..<itemCount {
            let id=try integer(reader,iloc,at,lv<2 ? 2:4);at+=UInt64(lv<2 ? 2:4)
            var method:UInt64=0
            if lv>0 {method=try integer(reader,iloc,at,2);at+=2}
            let reference=try integer(reader,iloc,at,2);at+=2
            guard method<=1,reference==0,infos[id] != nil,extents[id]==nil else {throw RestoreError(.unsupported,"HEIF external/derived data references require a separately qualified profile.")}
            let base=try integer(reader,iloc,at,baseSize);at+=UInt64(baseSize)
            let extentCount=try integer(reader,iloc,at,2);at+=2;totalExtents+=Int(extentCount)
            guard totalExtents<=100000 else {throw RestoreError(.unsupported,"HEIF extent count exceeds its bound.")}
            var ranges=[Extent]()
            for _ in 0..<extentCount {
                if indexSize>0 {guard try integer(reader,iloc,at,indexSize)==0 else {throw RestoreError(.unsupported,"Indexed HEIF construction is not qualified.")};at+=UInt64(indexSize)}
                let offset=try integer(reader,iloc,at,offsetSize);at+=UInt64(offsetSize)
                let length=try integer(reader,iloc,at,lengthSize);at+=UInt64(lengthSize)
                let origin:UInt64
                if method==1 {guard let idat=idats.first else {throw RestoreError(.malformedMetadata,"HEIF idat extent has no data box.")};origin=idat.content} else {origin=0}
                let sum=base.addingReportingOverflow(offset),absolute=origin.addingReportingOverflow(sum.partialValue)
                guard !sum.overflow,!absolute.overflow else {throw RestoreError(.malformedMetadata,"HEIF extent offset overflow.")}
                let containers=method==1 ? idats:mdats
                guard containers.contains(where:{absolute.partialValue >= $0.content && absolute.partialValue <= $0.end && length <= $0.end-absolute.partialValue}) else {throw RestoreError(.malformedMetadata,"HEIF item data is outside its media-data container.")}
                ranges.append(.init(offset:absolute.partialValue,length:length));coverage.append(.init(offset:absolute.partialValue,length:length))
            }
            extents[id]=ranges
        }
        guard at==iloc.end,Set(extents.keys)==Set(infos.keys) else {throw RestoreError(.malformedMetadata,"HEIF item/extent inventories do not agree.")}
        var protectedExtents=0
        for info in infos.values.sorted(by:{$0.id<$1.id}) {
            let ranges=extents[info.id] ?? []
            if !info.metadata {
                guard !ranges.isEmpty || info.type=="iden" else {throw RestoreError(.malformedMetadata,"A HEIF image has no encoded extents.")}
                for (index,range) in ranges.enumerated() {guard range.length>0 else {throw RestoreError(.malformedMetadata,"An empty HEIF image extent is unqualified.")};try digest.range(reader,range.offset,range.length,label:"item:\(info.id):\(index)",pixels:true);protectedExtents+=1}
            } else if info.type=="Exif" {
                guard ranges.count==1,let range=ranges.first,range.length>=4 else {throw RestoreError(.unsupported,"Fragmented HEIF EXIF storage is not qualified.")}
                let prefix=try reader.integer(range.offset,width:4)
                guard prefix<=range.length-4 else {throw RestoreError(.malformedMetadata,"Invalid HEIF EXIF header offset.")}
                let exif=try TIFFIntegrity().signature(reader,base:range.offset+4+prefix,length:range.length-4-prefix,metadataOnly:true),empty=FileIdentityReader.hash(Data())
                if exif.payloadHash != empty || exif.structureHash != empty {digest.field("Exif:"+exif.payloadHash+":"+exif.structureHash)}
            }
        }
        guard protectedExtents>0 else {throw RestoreError(.unsupported,"No HEIF encoded image payload was found.")}
        for iref in children.filter({$0.type=="iref"}) {
            let rv=try version(reader,iref,allowed:[0,1]),width=rv==0 ? 2:4
            for reference in try ISOBoxes.read(reader,start:iref.content+4,end:iref.end) {
                var cursor=reference.content
                let from=try integer(reader,reference,cursor,width);cursor+=UInt64(width)
                let count=try integer(reader,reference,cursor,2);cursor+=2;var targets=[UInt64]()
                for _ in 0..<count {targets.append(try integer(reader,reference,cursor,width));cursor+=UInt64(width)}
                guard cursor==reference.end,infos[from] != nil,targets.allSatisfy({infos[$0] != nil}) else {throw RestoreError(.malformedMetadata,"Invalid HEIF item relationship.")}
                let involvesMetadata=metadataIDs.contains(from) || targets.contains(where:{metadataIDs.contains($0)})
                if involvesMetadata {guard reference.type=="cdsc" else {throw RestoreError(.unsupported,"Rendering relationships to metadata items are not qualified.")}}
                else {digest.field("ref:\(reference.type):\(from):"+targets.map(String.init).joined(separator:","))}
            }
        }
        let iprp=try ISOBoxes.one(children,"iprp"),properties=try ISOBoxes.read(reader,start:iprp.content,end:iprp.end),ipco=try ISOBoxes.one(properties,"ipco")
        guard properties.allSatisfy({["ipco","ipma"].contains($0.type)}) else {throw RestoreError(.unsupported,"Unknown HEIF property container.")}
        let values=try ISOBoxes.read(reader,start:ipco.content,end:ipco.end)
        var associated=Set<UInt64>(),auxiliary=false,hdr=false
        for ipma in properties.filter({$0.type=="ipma"}) {
            let version=try self.version(reader,ipma,allowed:[0,1],allowFlags:true),flags=try integer(reader,ipma,ipma.content+1,3),width=version==0 ? 2:4
            guard flags & ~1 == 0 else {throw RestoreError(.unsupported,"Unqualified HEIF property-association flags.")}
            var cursor=ipma.content+4;let count=try integer(reader,ipma,cursor,4);cursor+=4
            guard count<=10000 else {throw RestoreError(.unsupported,"HEIF property associations exceed their bound.")}
            for _ in 0..<count {
                let id=try integer(reader,ipma,cursor,width);cursor+=UInt64(width)
                let num=try integer(reader,ipma,cursor,1);cursor+=1
                guard infos[id] != nil,associated.insert(id).inserted else {throw RestoreError(.malformedMetadata,"Unknown or duplicate HEIF property association.")}
                var codec=false,dimensions=false
                for _ in 0..<num {
                    let wide=flags&1==1,raw=try integer(reader,ipma,cursor,wide ? 2:1);cursor+=UInt64(wide ? 2:1)
                    let index=raw & (wide ? 0x7fff:0x7f),essential=raw & (wide ? 0x8000:0x80) != 0
                    guard index<=values.count else {throw RestoreError(.malformedMetadata,"HEIF property index exceeds ipco.")}
                    if index==0 {continue}
                    let property=values[Int(index)-1]
                    if !metadataIDs.contains(id) {
                        digest.field("property:\(id):\(property.type):\(essential)");try digest.range(reader,property.content,property.length,label:"property-data",pixels:false)
                        if property.type=="auxC" {auxiliary=true}
                        if property.type=="ispe" {dimensions=true}
                        // HEVCDecoderConfigurationRecord: independent luma/chroma depth fields.
                        // https://github.com/strukturag/libheif/blob/master/libheif/codecs/hevc_boxes.cc
                        if property.type=="hvcC" {codec=true;guard property.length>=23 else {throw RestoreError(.malformedMetadata,"Truncated HEVC image configuration.")};let luma=try reader.integer(property.content+17,width:1),chroma=try reader.integer(property.content+18,width:1);if luma&7 != 0 || chroma&7 != 0 {hdr=true}}
                        if property.type=="av1C" {codec=true;guard property.length>=4 else {throw RestoreError(.malformedMetadata,"Truncated AV1 image configuration.")};if try reader.integer(property.content+2,width:1)&0x40 != 0 {hdr=true}}
                        if property.type=="colr",property.length>=11,try reader.bytes(property.content,4)==Data("nclx".utf8) {let transfer=try reader.integer(property.content+6,width:2);if [UInt64(16),18].contains(transfer) {hdr=true}}
                    }
                }
                if let info=infos[id],!info.metadata {
                    guard dimensions else {throw RestoreError(.unsupported,"A HEIF image lacks qualified dimensions.")}
                    if ["hvc1","hev1","av01"].contains(info.type) && !codec {throw RestoreError(.unsupported,"A HEIF image lacks its codec configuration.")}
                }
            }
            guard cursor==ipma.end else {throw RestoreError(.malformedMetadata,"Trailing HEIF association data.")}
        }
        guard Set(infos.values.filter({!$0.metadata}).map(\.id)).isSubset(of:associated) else {throw RestoreError(.unsupported,"A HEIF image has no understood property associations.")}
        guard !auxiliary || allowQualifiedAuxiliary else {throw RestoreError(.unsupported,"HEIF auxiliary/depth/gain-map writing awaits genuine fixture qualification.")}
        guard !hdr || allowQualifiedHDR else {throw RestoreError(.unsupported,"HEIF HDR/high-bit-depth writing awaits genuine fixture qualification.")}
        let ranges=coverage.sorted {$0.offset<$1.offset}
        for container in mdats+idats {
            var end=container.content
            for range in ranges where range.offset>=container.content && range.offset<container.end {
                if range.offset>end {try requireZero(reader,start:end,end:range.offset)}
                end=max(end,range.offset+range.length)
            }
            if end<container.end {try requireZero(reader,start:end,end:container.end)}
        }
        return digest.signature(profile:profile,validator:"heif-items-v1")
    }
    private func requireZero(_ reader:BoundedMediaReader,start:UInt64,end:UInt64) throws {
        var at=start
        while at<end {let n=Int(min(end-at,1_048_576));guard try !reader.bytes(at,n).contains(where:{$0 != 0}) else {throw RestoreError(.unsupported,"Unreferenced HEIF data requires an additional integrity profile.")};at+=UInt64(n)}
    }
    private func version(_ reader:BoundedMediaReader,_ box:ISOBox,allowed:[UInt64],allowFlags:Bool=false) throws -> UInt64 {
        let v=try integer(reader,box,box.content,1)
        guard allowed.contains(v),try allowFlags || integer(reader,box,box.content+1,3)==0 else {throw RestoreError(.unsupported,"Unsupported \(box.type) full-box version/flags.")};return v
    }
    private func integer(_ reader:BoundedMediaReader,_ box:ISOBox,_ at:UInt64,_ width:Int) throws -> UInt64 {guard at>=box.content,at<=box.end,UInt64(width)<=box.end-at else {throw RestoreError(.malformedMetadata,"Truncated \(box.type) field.")};return try reader.integer(at,width:width)}
    private func bytes(_ reader:BoundedMediaReader,_ box:ISOBox,_ at:UInt64,_ count:Int) throws -> Data {guard at>=box.content,at<=box.end,UInt64(count)<=box.end-at else {throw RestoreError(.malformedMetadata,"Truncated \(box.type) field.")};return try reader.bytes(at,count)}
    private func zstring(_ reader:BoundedMediaReader,_ box:ISOBox,_ at:inout UInt64) throws -> String {
        let data=try bytes(reader,box,at,Int(min(4096,box.end-at)))
        guard let end=data.firstIndex(of:0) else {throw RestoreError(.unsupported,"Unterminated or excessive HEIF item string.")}
        at+=UInt64(end+1);return String(decoding:data.prefix(end),as:UTF8.self)
    }
}
