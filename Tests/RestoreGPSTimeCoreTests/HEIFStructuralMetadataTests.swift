import XCTest
@testable import RestoreGPSTimeCore

final class HEIFStructuralMetadataTests:MetadataStageTestCase {
    // hvcC fields emitted by the bundled ExifTool HEVCConfig decoder. These are
    // structural codec observations, never supported editable tag selectors.
    private let codecFields:[String:Any] = [
        "HEVCConfigurationVersion":1,"GeneralProfileSpace":0,"GeneralTierFlag":0,
        "GeneralProfileIDC":3,"GenProfileCompatibilityFlags":1879048192,
        "ConstraintIndicatorFlags":"176 0 0 0 0 0","GeneralLevelIDC":30,
        "MinSpatialSegmentationIDC":0,"ParallelismType":0,"ChromaFormat":1,
        "BitDepthLuma":8,"BitDepthChroma":8,"AverageFrameRate":0,
        "ConstantFrameRate":0,"NumTemporalLayers":1,"TemporalIDNested":0
    ]
    private func decode(_ fields:[String:Any]) throws -> MetadataDocument {
        try MetadataDecoder().decode(JSONSerialization.data(withJSONObject:[fields]))
    }
    private func fields(profile:String="HEIC") -> [String:Any] {
        var result:[String:Any] = ["File:FileType":profile]
        for (name,value) in codecFields {result["QuickTime:"+name]=value;result["QuickTime:Copy1:"+name]=value}
        return result
    }
    func testHEICAndHEIFCodecRepetitionsPermitUnchangedMetadataDiff() throws {
        for profile in ["HEIC","HEIF"] {
            let document=try decode(fields(profile:profile))
            XCTAssertEqual(document.repeatedIdentifiers.count,16)
            XCTAssertNoThrow(try document.requireQualifiedLayout(),profile)
            XCTAssertNoThrow(try MetadataMutationDriver.verifyDiff(before:document,after:document,tags:[],stripping:false),profile)
            for name in codecFields.keys {
                XCTAssertThrowsError(try TagRegistry().validate([.set(TagID(rawValue:"QuickTime:"+name)!,.integer(0))],profile:document.profile))
            }
        }
    }
    func testCodecOccurrencesMayBeRelabeledButEveryValueAndCountRemainProtected() throws {
        var original=fields();original["QuickTime:Copy1:GeneralLevelIDC"]=60
        let before=try decode(original)
        var reordered=fields();reordered["QuickTime:GeneralLevelIDC"]=60
        reordered.removeValue(forKey:"QuickTime:Copy1:GeneralLevelIDC");reordered["QuickTime:Copy3:GeneralLevelIDC"]=30
        XCTAssertNoThrow(try MetadataMutationDriver.verifyDiff(before:before,after:decode(reordered),tags:[],stripping:false))
        for name in codecFields.keys {
            var changed=original;changed["QuickTime:Copy1:"+name]="changed"
            XCTAssertThrowsError(try MetadataMutationDriver.verifyDiff(before:before,after:decode(changed),tags:[],stripping:false),name)
            var removed=original;removed.removeValue(forKey:"QuickTime:Copy1:"+name)
            XCTAssertThrowsError(try MetadataMutationDriver.verifyDiff(before:before,after:decode(removed),tags:[],stripping:false),name)
            var added=original;added["QuickTime:Copy2:"+name]=codecFields[name]
            XCTAssertThrowsError(try MetadataMutationDriver.verifyDiff(before:before,after:decode(added),tags:[],stripping:false),name)
        }
    }
    func testEditableUnknownAndOtherContainerRepetitionsStillBlock() throws {
        for id in ["ExifIFD:UserComment","ExifIFD:DateTimeOriginal","GPS:GPSLatitude","XMP-dc:Description","QuickTime:UnknownCodecField","QuickTime:ImageSpatialExtent"] {
            for value in ["same","different"] {
                var repeated=fields();repeated[id]="same"
                let parts=id.split(separator:":");repeated["\(parts[0]):Copy1:\(parts[1])"]=value
                XCTAssertThrowsError(try decode(repeated).requireQualifiedLayout(),id)
            }
        }
        for profile in ["AVIF","JPEG","MOV","UNKNOWN"] {XCTAssertThrowsError(try decode(fields(profile:profile)).requireQualifiedLayout(),profile)}
    }
    func testCodecQualificationDoesNotSuppressHelperDiagnostics() throws {
        var diagnostic=fields();diagnostic["ExifTool:Warning"]="Generated warning"
        let document=try decode(diagnostic)
        XCTAssertEqual(document.diagnostics,["Generated warning"])
        XCTAssertThrowsError(try MetadataMutationDriver.verifyDiff(before:document,after:document,tags:[],stripping:false))
    }
    func testGeneratedHEICRepeatedCodecWritePreservesCompleteOccurrencesAndMedia() async throws {
        let stage=try ownedStage("paris.heic")
        try duplicateCodecProperty(at:stage)
        try StageOwnership.shared.refresh(stage)
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths)
        let before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
        XCTAssertTrue(before.diagnostics.isEmpty)
        XCTAssertEqual(before.repeatedIdentifiers,Set(codecFields.keys.map {"QuickTime:"+$0}))
        let validator=MediaIntegrityValidator(),signature=try await validator.signature(at:stage,profile:before.profile)
        let tag=TagID(rawValue:"ExifIFD:UserComment")!
        let result=try await MetadataMutationDriver(paths:paths).apply(.init(tags:[.set(tag,.string("Generated repeated HEVC configuration"))],profile:before.profile,allowedMetadataChanges:.init(tags:[tag.rawValue])),to:stage)
        XCTAssertEqual(result.integrityValidator,"heif-items-v1")
        let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
        XCTAssertEqual(after.tags[tag.rawValue]?.text,"Generated repeated HEVC configuration")
        for name in codecFields.keys {
            XCTAssertEqual(before.values(for:"QuickTime:"+name).count,2)
            XCTAssertTrue(try MetadataDocument.sameValues(before.values(for:"QuickTime:"+name),after.values(for:"QuickTime:"+name)),name)
        }
        let afterSignature=try await validator.signature(at:stage,profile:after.profile)
        XCTAssertEqual(signature,afterSignature)
        // Altering a protected hvcC byte must still invalidate the media signature.
        let bounded=try BoundedMediaReader(stage),root=try ISOBoxes.read(bounded,start:0,end:bounded.size)
        let meta=try ISOBoxes.one(root,"meta"),children=try ISOBoxes.read(bounded,start:meta.content+4,end:meta.end)
        let iprp=try ISOBoxes.one(children,"iprp"),propertyContainers=try ISOBoxes.read(bounded,start:iprp.content,end:iprp.end)
        let ipco=try ISOBoxes.one(propertyContainers,"ipco"),properties=try ISOBoxes.read(bounded,start:ipco.content,end:ipco.end)
        let codec=try XCTUnwrap(properties.first {$0.type=="hvcC"})
        var altered=try Data(contentsOf:stage);altered[Int(codec.content+12)] ^= 1;try altered.write(to:stage)
        let alteredSignature=try await validator.signature(at:stage,profile:after.profile)
        XCTAssertThrowsError(try validator.verify(before:afterSignature,after:alteredSignature,allowedChanges:.init()))
    }
    func testRepeatedCodecQualificationStillRejectsSyntheticHighBitDepthBeforeWriting() async throws {
        let stage=try ownedStage("paris.heic")
        try duplicateCodecProperty(at:stage)
        let reader=try BoundedMediaReader(stage),root=try ISOBoxes.read(reader,start:0,end:reader.size)
        let meta=try ISOBoxes.one(root,"meta"),children=try ISOBoxes.read(reader,start:meta.content+4,end:meta.end)
        let iprp=try ISOBoxes.one(children,"iprp"),containers=try ISOBoxes.read(reader,start:iprp.content,end:iprp.end)
        let ipco=try ISOBoxes.one(containers,"ipco"),properties=try ISOBoxes.read(reader,start:ipco.content,end:ipco.end)
        var bytes=try Data(contentsOf:stage)
        for property in properties where property.type=="hvcC" {bytes[Int(property.content+17)] |= 2}
        try bytes.write(to:stage,options:.atomic);try StageOwnership.shared.refresh(stage)
        let paths=try RuntimeLocator().locate(in:testApp)
        let document=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:stage))
        XCTAssertNoThrow(try document.requireQualifiedLayout())
        let tag=TagID(rawValue:"ExifIFD:UserComment")!
        do {
            _ = try await MetadataMutationDriver(paths:paths).apply(.init(tags:[.set(tag,.string("Must remain blocked"))],profile:document.profile,allowedMetadataChanges:.init(tags:[tag.rawValue])),to:stage)
            XCTFail("Structural metadata qualification must not bypass the HDR integrity gate")
        } catch let error as RestoreError {XCTAssertEqual(error.code,.unsupported);XCTAssertTrue(error.detail.contains("HDR/high-bit-depth"))}
        XCTAssertEqual(try Data(contentsOf:stage),bytes)
    }
    // Extend only the generated baseline fixture. Its version-0 iloc uses 32-bit
    // absolute offsets, so insertion requires explicit relocation of each extent.
    private func duplicateCodecProperty(at file:URL) throws {
        let reader=try BoundedMediaReader(file),root=try ISOBoxes.read(reader,start:0,end:reader.size)
        let meta=try ISOBoxes.one(root,"meta"),children=try ISOBoxes.read(reader,start:meta.content+4,end:meta.end)
        let iprp=try ISOBoxes.one(children,"iprp"),containers=try ISOBoxes.read(reader,start:iprp.content,end:iprp.end)
        let ipco=try ISOBoxes.one(containers,"ipco"),properties=try ISOBoxes.read(reader,start:ipco.content,end:ipco.end)
        let codec=try ISOBoxes.one(properties,"hvcC"),iloc=try ISOBoxes.one(children,"iloc")
        var data=try Data(contentsOf:file)
        func write(_ value:UInt64,at offset:UInt64,width:Int) {
            data.replaceSubrange(Int(offset)..<Int(offset)+width,with:(0..<width).reversed().map {UInt8(truncatingIfNeeded:value>>($0*8))})
        }
        XCTAssertEqual(try reader.integer(iloc.content,width:4),0)
        XCTAssertEqual(try reader.integer(iloc.content+4,width:2),0x4400)
        guard try reader.integer(iloc.content,width:4)==0,try reader.integer(iloc.content+4,width:2)==0x4400 else {throw RestoreError(.unsupported,"Generated fixture iloc format changed")}
        let count=try reader.integer(iloc.content+6,width:2)
        var cursor=iloc.content+8
        for _ in 0..<count {
            let extents=try reader.integer(cursor+4,width:2);cursor+=6
            for _ in 0..<extents {
                let offset=try reader.integer(cursor,width:4)
                guard offset>=ipco.end else {throw RestoreError(.unsupported,"Generated fixture extent precedes insertion")}
                write(offset+codec.size,at:cursor,width:4);cursor+=8
            }
        }
        XCTAssertEqual(cursor,iloc.end)
        for box in [meta,iprp,ipco] {
            guard box.header==8 else {throw RestoreError(.unsupported,"Generated fixture box header changed")}
            write(box.size+codec.size,at:box.start,width:4)
        }
        let extra=try reader.bytes(codec.start,Int(codec.size))
        data.insert(contentsOf:extra,at:Int(ipco.end))
        try data.write(to:file,options:.atomic)
    }
}
