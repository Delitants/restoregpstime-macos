import XCTest
@testable import RestoreGPSTimeCore

final class ExactCaptureFractionTests:MetadataStageTestCase {
    func testNativeNineDigitMetadataAndFileTimesRoundTripWithoutMediaChanges() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths),writer=ExifToolWriter(paths:paths),driver=AttributeMutationDriver(paths:paths)
        for (fixture,nanos) in [("paris.jpg","123456789"),("paris.heic","123456789"),("paris.png","123456789"),("paris.mov","123456789"),("paris.jpg","000000001")] {
            let stage=try ownedStage(fixture),before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            let photo=["JPEG","HEIC"].contains(before.profile.identifier),video=before.profile.family == .video
            let sourceTag=photo ? "ExifIFD:DateTimeOriginal":(video ? "Keys:CreationDate":"XMP-exif:DateTimeOriginal")
            let source:[TagMutation]=photo ? [.set(TagID(rawValue:sourceTag)!,.string("2024:01:02 03:04:05")),.set(TagID(rawValue:"ExifIFD:OffsetTimeOriginal")!,.string("+02:00")),.set(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!,.string(nanos))]:[.set(TagID(rawValue:sourceTag)!,.string("2024:01:02 03:04:05."+nanos+"+02:00"))]
            _=try await writer.write(source,to:stage,profile:before.profile)
            let snapshot=try FileIdentityReader().snapshot(at:stage),document=try await reader.read(snapshot:snapshot)
            var policy=DatePolicy();policy.source = .tag(sourceTag);policy.targets=[.creation,.modification,.capture];policy.shiftSeconds=3600
            let resolved=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:policy),mutation=try DateMutationPlanner().plan(resolution:resolved,policy:policy,snapshot:snapshot,sequenceIndex:0)
            let signature=try await MediaIntegrityValidator().signature(at:stage,profile:document.profile)
            _=try await driver.apply(.init(dates:mutation,profile:document.profile),to:stage)
            let after=try FileIdentityReader().snapshot(at:stage),written=try await reader.read(snapshot:after),expected=try FileTimestamp(seconds:Int64(try utc("2024-01-02T02:04:05Z").timeIntervalSince1970),nanoseconds:Int32(nanos)!)
            XCTAssertEqual(after.creationTimestamp,expected,fixture);XCTAssertEqual(after.modificationTimestamp,expected,fixture)
            let actualTags=try EmbeddedDateTags().mutations(mutation,profile:document.profile,document:document)
            for tag in actualTags {if case .set(let id,let value)=tag {XCTAssertEqual(TagRegistry().value(for:id,in:written)?.text,value.text,fixture+" "+id.rawValue)}}
            let finalSignature=try await MediaIntegrityValidator().signature(at:stage,profile:document.profile)
            XCTAssertEqual(finalSignature,signature,fixture)
        }
    }
    func testNineDigitEXIFCompanionFractionSurvivesWholeSecondShift() throws {
        let snapshot=try FileIdentityReader().snapshot(at:ownedStage("paris.jpg"))
        let document=MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05"),"ExifIFD:OffsetTimeOriginal":.string("+02:00"),"ExifIFD:SubSecTimeOriginal":.string("123456789")],profile:.init(identifier:"JPEG",family:.photo))
        var policy=DatePolicy();policy.targets = .capture;policy.shiftSeconds=3600
        let resolved=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:policy),change=try DateMutationPlanner().plan(resolution:resolved,policy:policy,snapshot:snapshot,sequenceIndex:0)
        let mutations=try EmbeddedDateTags().mutations(change,profile:document.profile,document:document)
        XCTAssertTrue(mutations.contains {.set(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!,.string("123456789")) == $0})
        XCTAssertTrue(mutations.contains {.set(TagID(rawValue:"ExifIFD:DateTimeOriginal")!,.string("2024:01:02 04:04:05")) == $0})
    }
    func testNineDigitXMPFractionSurvivesWholeSecondShift() throws {
        let snapshot=try FileIdentityReader().snapshot(at:ownedStage("paris.png"))
        let document=MetadataDocument(tags:["XMP-exif:DateTimeOriginal":.string("2024-01-02T03:04:05.123456789+02:00")],profile:.init(identifier:"PNG",family:.photo))
        var policy=DatePolicy();policy.targets = .capture;policy.shiftSeconds = -3600
        let resolved=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:policy),change=try DateMutationPlanner().plan(resolution:resolved,policy:policy,snapshot:snapshot,sequenceIndex:0)
        let mutations=try EmbeddedDateTags().mutations(change,profile:document.profile,document:document)
        XCTAssertTrue(mutations.contains {.set(TagID(rawValue:"XMP-exif:DateTimeOriginal")!,.string("2024-01-02T02:04:05.123456789+02:00")) == $0})
    }
}
