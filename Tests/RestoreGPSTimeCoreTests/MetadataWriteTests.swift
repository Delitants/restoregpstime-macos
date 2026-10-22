import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class MetadataWriteTests:MetadataStageTestCase {
    func testCreationToEmbeddedCaptureUsesSelectedOutputZone() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),snapshot=try FileIdentityReader().snapshot(at:stage)
        var policy=DatePolicy();policy.source = .fileCreation;policy.targets = .capture;policy.timeZoneID="Europe/Paris"
        let resolution=try CaptureDateResolver().resolve(document:.init(tags:[:]),snapshot:snapshot,policy:policy)
        let change=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:snapshot,sequenceIndex:0)
        let expected=try XCTUnwrap(TimeZone(identifier:"Europe/Paris")).secondsFromGMT(for:snapshot.creationDate)
        XCTAssertEqual(change.embeddedOffsetSeconds,expected)
        _ = try await MetadataMutationDriver(paths:paths).apply(.init(dates:change,profile:.init(identifier:"JPEG",family:.photo)),to:stage)
        let document=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:stage))
        let actual=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy())
        XCTAssertEqual(actual.instant.timeIntervalSince1970,snapshot.creationDate.timeIntervalSince1970,accuracy:0.000001)
        XCTAssertEqual(actual.offsetSeconds,expected)
    }
    func testSelectedTagRemovalKeepsUnselectedValues() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),profile=ContainerProfile(identifier:"JPEG",family:.photo),writer=ExifToolWriter(paths:paths)
        let selected=TagID(rawValue:"ExifIFD:UserComment")!,other=TagID(rawValue:"XMP-dc:Description-fr")!
        _ = try await writer.write([.set(selected,.string("remove only this")),.set(other,.string("À Paris"))],to:stage,profile:profile)
        let before=try await MediaIntegrityValidator().signature(at:stage,profile:profile)
        _ = try await MetadataMutationDriver(paths:paths).apply(.init(tags:[.remove(selected)],profile:profile,allowedMetadataChanges:.init(tags:[selected.rawValue])),to:stage)
        let document=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:stage))
        XCTAssertNil(document.tags[selected.rawValue]);XCTAssertEqual(TagRegistry().value(for:other,in:document)?.text,"À Paris")
        let after=try await MediaIntegrityValidator().signature(at:stage,profile:profile);XCTAssertEqual(before,after)
    }
    func testCaptureShiftAndRemovalFollowExistingPhotoDateFamily() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths)
        for file in ["paris.jpg","paris.heic","paris.png","paris.tiff","paris.mov"] {
            let stage=try ownedStage(file),snapshot=try FileIdentityReader().snapshot(at:stage),before=try await reader.read(snapshot:snapshot)
            let resolution=try CaptureDateResolver().resolve(document:before,snapshot:snapshot,policy:DatePolicy())
            var policy=DatePolicy();policy.targets = .capture;policy.shiftSeconds=900.25
            let change=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:snapshot,sequenceIndex:0),driver=MetadataMutationDriver(paths:paths)
            _ = try await driver.apply(.init(dates:change,profile:before.profile),to:stage)
            let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage)),adjusted=try CaptureDateResolver().resolve(document:after,snapshot:snapshot,policy:DatePolicy())
            XCTAssertEqual(adjusted.instant.timeIntervalSince1970,resolution.instant.timeIntervalSince1970+900.25,accuracy:0.000001,file)
            XCTAssertEqual(after.tags["ExifIFD:CreateDate"],before.tags["ExifIFD:CreateDate"])
            var remove=change;remove.embeddedDate=nil;remove.removeEmbeddedDates=true
            _ = try await driver.apply(.init(dates:remove,profile:before.profile),to:stage)
            let removed=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            XCTAssertNil(removed.tags[before.profile.family == .video ? "Keys:CreationDate":"ExifIFD:DateTimeOriginal"],file)
        }
        var unrelated=DatePolicy();unrelated.targets = .creation;unrelated.removeEmbeddedDates=true
        let snapshot=try FileIdentityReader().snapshot(at:fixture("paris.jpg")),resolution=CaptureDateResolver.instant(Date(),source:"test")
        let mutation=try DateMutationPlanner().plan(resolution:resolution,policy:unrelated,snapshot:snapshot,sequenceIndex:0)
        XCTAssertFalse(mutation.removeEmbeddedDates,"Unselected capture timestamps must remain unchanged")
    }
    func testEmbeddedDatesKeepFractionalAbsoluteAndAdjustedInstants() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),snapshot=try FileIdentityReader().snapshot(at:stage)
        var policy=DatePolicy();policy.source = .specific(try utc("2024-01-02T01:04:05Z").addingTimeInterval(0.125));policy.targets = .capture;policy.shiftSeconds=0.25
        let resolution=try CaptureDateResolver().resolve(document:.init(tags:[:]),snapshot:snapshot,policy:policy)
        let change=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:snapshot,sequenceIndex:0)
        let driver=MetadataMutationDriver(paths:paths)
        _ = try await driver.apply(.init(dates:change,profile:.init(identifier:"JPEG",family:.photo)),to:stage)
        let doc=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:stage))
        let result=try CaptureDateResolver().resolve(document:doc,snapshot:snapshot,policy:DatePolicy())
        XCTAssertEqual(result.instant.timeIntervalSince1970,try utc("2024-01-02T01:04:05Z").timeIntervalSince1970+0.375,accuracy:0.000001)
        var sequence=DatePolicy();sequence.targets = .capture;sequence.sequenceStart=try utc("2024-01-02T01:04:05Z");sequence.sequenceStepSeconds=0.125
        let next=try DateMutationPlanner().plan(resolution:resolution,policy:sequence,snapshot:snapshot,sequenceIndex:2)
        let tags=try EmbeddedDateTags().mutations(next,profile:.init(identifier:"JPEG",family:.photo))
        XCTAssertTrue(tags.contains {if case .set(let id,let value)=$0 {return id.rawValue=="ExifIFD:SubSecTimeOriginal" && value.text.hasPrefix("25")};return false})
    }
    func testVideoRejectsUnqualifiedExifWritesAndAggregateBounds() throws {
        XCTAssertThrowsError(try TagRegistry().validate([.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("not qualified"))],profile:.init(identifier:"MOV",family:.video)))
        let list=TagValue.array(Array(repeating:.string(String(repeating:"x",count:65536)),count:32))
        XCTAssertThrowsError(try TagRegistry().validate([.set(TagID(rawValue:"XMP-dc:Subject")!,list)],profile:.init(identifier:"JPEG",family:.photo)))
    }
    func testWebPAndAVIFRoundTrip() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),writer=ExifToolWriter(paths:paths),reader=MetadataReader(paths:paths)
        for file in ["geometric-baseline.webp","geometric-baseline.avif"] {
            let stage=try ownedStage(file),before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            let integrity=MediaIntegrityValidator(),signature=try await integrity.signature(at:stage,profile:before.profile)
            let tag=TagID(rawValue:"XMP-dc:Description-x-default")!,value="Paris, France – 東京"
            let after=try await writer.write([.set(tag,.string(value))],to:stage,profile:before.profile)
            XCTAssertEqual(TagRegistry().value(for:tag,in:after)?.text,value)
            let finalSignature=try await integrity.signature(at:stage,profile:before.profile)
            XCTAssertEqual(signature,finalSignature)
        }
    }
    func testDatesAndLocationRoundTrip() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths),writer=ExifToolWriter(paths:paths)
        for file in ["paris.jpg","paris.heic","paris.tiff","paris.png","paris.mov","geometric-baseline.mp4"] {
            let stage=try ownedStage(file),before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            let integrity=MediaIntegrityValidator(),signature=try await integrity.signature(at:stage,profile:before.profile)
            let mutations:[TagMutation]
            let comment:String
            if before.profile.family == .video {
                mutations=[.set(TagID(rawValue:"Keys:CreationDate")!,.string("2022:03:04 05:06:07.456+03:00")),.set(TagID(rawValue:"Keys:Description-und")!,.string("Paris, France"))];comment="Keys:Description-und"
            } else {
                mutations=[.set(TagID(rawValue:"ExifIFD:DateTimeOriginal")!,.string("2022:03:04 05:06:07")),.set(TagID(rawValue:"ExifIFD:OffsetTimeOriginal")!,.string("+03:00")),.set(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!,.string("456")),.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("Paris, France"))];comment="ExifIFD:UserComment"
            }
            let after=try await writer.write(mutations,to:stage,profile:before.profile)
            XCTAssertEqual(TagRegistry().value(for:TagID(rawValue:comment)!,in:after)?.text,"Paris, France")
            let date=try CaptureDateResolver().resolve(document:after,snapshot:FileIdentityReader().snapshot(at:stage),policy:DatePolicy())
            XCTAssertEqual(date.instant.timeIntervalSince1970,try utc("2022-03-04T02:06:07Z").timeIntervalSince1970+0.456,accuracy:0.000001)
            let newSignature=try await integrity.signature(at:stage,profile:before.profile)
            XCTAssertEqual(signature,newSignature,"Stored media changed in \(file)")
        }
    }
    func testUnicodeCommentsAndLanguageAlternatives() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),profile=ContainerProfile(identifier:"JPEG",family:.photo),writer=ExifToolWriter(paths:paths)
        _ = try await writer.write([.set(TagID(rawValue:"XMP-dc:Description-fr")!,.string("À Paris")),.set(TagID(rawValue:"XMP-dc:Description-x-default")!,.string("東京 – Paris")),.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("東京 – Paris"))],to:stage,profile:profile)
        let after=try await writer.write([.set(TagID(rawValue:"XMP-dc:Description-x-default")!,.string("Replacement"))],to:stage,profile:profile)
        XCTAssertEqual(TagRegistry().value(for:TagID(rawValue:"XMP-dc:Description-fr")!,in:after)?.text,"À Paris")
        XCTAssertEqual(TagRegistry().value(for:TagID(rawValue:"ExifIFD:UserComment")!,in:after)?.text,"東京 – Paris")
    }
    func testListsRetainTypes() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),profile=ContainerProfile(identifier:"JPEG",family:.photo)
        for entries in [[TagValue.string("one"),.string("two"),.string("日本語")],[.string("only one")],[]] {
            let values=TagValue.array(entries)
            let after=try await ExifToolWriter(paths:paths).write([.set(TagID(rawValue:"XMP-dc:Subject")!,values)],to:stage,profile:profile)
            if entries.isEmpty {XCTAssertNil(after.tags["XMP-dc:Subject"])} else {XCTAssertEqual(after.tags["XMP-dc:Subject"],values)}
        }
    }
    func testTagValuesAreLiteral() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),marker=workspace.appendingPathComponent("must-not-exist")
        let text="$(touch \(marker.path)) -execute\n<xml>&東京"
        let after=try await ExifToolWriter(paths:paths).write([.set(TagID(rawValue:"ExifIFD:UserComment")!,.string(text))],to:stage,profile:.init(identifier:"JPEG",family:.photo))
        XCTAssertEqual(after.tags["ExifIFD:UserComment"]?.text,text);XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path))
    }
    func testDriverVerifiesPayloadAndUnselectedAttributes() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),tag=TagID(rawValue:"ExifIFD:UserComment")!
        for (key,value) in [("com.apple.ResourceFork",Data("synthetic resource fork".utf8)),("com.restoregpstime.test",Data("preserve me".utf8)),("com.apple.FinderInfo",Data(repeating:0x12,count:32))] {
            XCTAssertEqual(value.withUnsafeBytes {setxattr(stage.path,key,$0.baseAddress,value.count,0,XATTR_NOFOLLOW)},0)
        }
        let before=try FileIdentityReader().fingerprint(at:stage)
        let mutation=MutationPlan(tags:[.set(tag,.string("Driver checked"))],profile:.init(identifier:"JPEG",family:.photo),allowedMetadataChanges:.init(tags:[tag.rawValue]))
        let result=try await MetadataMutationDriver(paths:paths).apply(mutation,to:stage)
        let after=try FileIdentityReader().fingerprint(at:stage)
        XCTAssertEqual(result.contentHash,after.contentHash);XCTAssertNotEqual(result.integrityValidator,"sha256-v1")
        XCTAssertNotEqual(before.contentHash,after.contentHash)
        XCTAssertEqual(after.snapshot.creationDate,before.snapshot.creationDate);XCTAssertEqual(after.snapshot.modificationDate,before.snapshot.modificationDate)
        XCTAssertEqual(after.snapshot.xattrHashes,before.snapshot.xattrHashes);XCTAssertEqual(after.snapshot.aclText,before.snapshot.aclText);XCTAssertEqual(after.snapshot.permissions,before.snapshot.permissions)
        let doc=try await MetadataReader(paths:paths).read(snapshot:after.snapshot)
        XCTAssertEqual(doc.tags[tag.rawValue]?.text,"Driver checked")
    }
    func testDriverRejectsUnplannedTagScope() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),before=try FileIdentityReader().fingerprint(at:stage)
        let mutation=MutationPlan(tags:[.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("Unplanned"))],profile:.init(identifier:"JPEG",family:.photo))
        do {_ = try await MetadataMutationDriver(paths:paths).apply(mutation,to:stage);XCTFail("The driver must bind writes to the frozen tag scope")} catch is RestoreError {}
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:stage))
    }
    func testUnknownReadOnlyTagBlocks() throws {
        for tag in ["ExifIFD:MakerNote","File:FileName","System:FileModifyDate"] {
            XCTAssertThrowsError(try TagRegistry().validate([.set(TagID(rawValue:tag)!,.string("unexpected"))],profile:.init(identifier:"JPEG",family:.photo)))
        }
        XCTAssertNil(TagID(rawValue:"XMP-dc:Description\n"))
        let malicious=Data("{\"rawValue\":\"-config /tmp/example\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TagID.self,from:malicious))
    }
    func testWriterRefusesSourcePaths() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),source=try fixture("paris.jpg"),before=try FileIdentityReader().fingerprint(at:source)
        do {_ = try await ExifToolWriter(paths:paths).write([.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("must not write"))],to:source,profile:.init(identifier:"JPEG",family:.photo));XCTFail("A user source is not an owned stage")} catch is RestoreError {}
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:source))
    }
}
