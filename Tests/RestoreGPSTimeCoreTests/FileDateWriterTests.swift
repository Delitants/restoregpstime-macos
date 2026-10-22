import XCTest
@testable import RestoreGPSTimeCore

final class FileDateWriterTests:MetadataStageTestCase {
    func testCopyModificationToCreation() async throws {try await sourceAction(.fileModification,targets:.creation)}
    func testCopyCreationToModification() async throws {try await sourceAction(.fileCreation,targets:.modification)}
    func testEmbeddedCaptureToCreation() async throws {try await sourceAction(.automaticCapture,targets:.creation)}
    func testShiftCreation() async throws {try await sourceAction(.fileCreation,targets:.creation,shift:7200)}
    func testShiftModification() async throws {try await sourceAction(.fileModification,targets:.modification,shift:-7200)}
    func testShiftBothDates() async throws {try await sourceAction(.fileCreation,targets:[.creation,.modification],shift:7200,independent:true)}
    private func sourceAction(_ source:SourceChoice,targets:DateTargets,shift:Double=0,independent:Bool=false) async throws {
        let stage=try ownedStage("paris.jpg"),birth=try utc("2010-01-02T03:04:05Z"),modified=try utc("2012-06-07T08:09:10Z")
        _ = try FileDateWriter().apply(.init(creationDate:birth,modificationDate:modified),to:stage)
        let before=try FileIdentityReader().fingerprint(at:stage),paths=try RuntimeLocator().locate(in:testApp),document=try await MetadataReader(paths:paths).read(snapshot:before.snapshot)
        var policy=DatePolicy();policy.source=source;policy.targets=targets;policy.shiftSeconds=shift;policy.shiftOriginalTargets=independent
        let resolution=try CaptureDateResolver().resolve(document:document,snapshot:before.snapshot,policy:policy)
        let change=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:before.snapshot,sequenceIndex:0)
        _ = try await AttributeMutationDriver(paths:paths).apply(.init(dates:change,profile:document.profile),to:stage)
        let after=try FileIdentityReader().fingerprint(at:stage)
        let expectedBirth=targets.contains(.creation) ? (independent ? birth:resolution.instant).addingTimeInterval(shift):birth
        let expectedModified=targets.contains(.modification) ? (independent ? modified:resolution.instant).addingTimeInterval(shift):modified
        XCTAssertEqual(after.snapshot.creationDate.timeIntervalSince1970,expectedBirth.timeIntervalSince1970,accuracy:0.000001)
        XCTAssertEqual(after.snapshot.modificationDate.timeIntervalSince1970,expectedModified.timeIntervalSince1970,accuracy:0.000001)
        XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertEqual(after.snapshot.xattrHashes,before.snapshot.xattrHashes)
    }
    func testShiftCreationAndCapture() async throws {
        let stage=try ownedStage("paris.jpg"),paths=try RuntimeLocator().locate(in:testApp),before=try FileIdentityReader().snapshot(at:stage),reader=MetadataReader(paths:paths)
        let document=try await reader.read(snapshot:before)
        var policy=DatePolicy();policy.targets=[.creation,.capture];policy.shiftOriginalTargets=true;policy.shiftSeconds=3600
        let original=try CaptureDateResolver().resolve(document:document,snapshot:before,policy:policy)
        let change=try DateMutationPlanner().plan(resolution:original,policy:policy,snapshot:before,sequenceIndex:0)
        _ = try await AttributeMutationDriver(paths:paths).apply(.init(dates:change,profile:document.profile),to:stage)
        let snapshot=try FileIdentityReader().snapshot(at:stage),after=try await reader.read(snapshot:snapshot)
        let capture=try CaptureDateResolver().resolve(document:after,snapshot:snapshot,policy:DatePolicy())
        XCTAssertEqual(snapshot.creationDate,before.creationDate.addingTimeInterval(3600));XCTAssertEqual(snapshot.modificationDate,before.modificationDate)
        XCTAssertEqual(capture.instant.timeIntervalSince1970,original.instant.timeIntervalSince1970+3600,accuracy:0.000001)
    }
    func testSetCreationDate() throws {try check(creation:true,modification:false)}
    func testSetModificationDate() throws {try check(creation:false,modification:true)}
    func testSetBothDates() throws {try check(creation:true,modification:true)}
    private func check(creation:Bool,modification:Bool) throws {
        let stage=try ownedStage("paris.jpg"),before=try FileIdentityReader().fingerprint(at:stage),date=try utc("2020-02-03T04:05:06Z").addingTimeInterval(0.125)
        let result=try FileDateWriter().apply(.init(creationDate:creation ? date:nil,modificationDate:modification ? date:nil),to:stage)
        XCTAssertEqual(result.snapshot.creationDate,creation ? date:before.snapshot.creationDate)
        XCTAssertEqual(result.snapshot.modificationDate,modification ? date:before.snapshot.modificationDate)
        let after=try FileIdentityReader().fingerprint(at:stage)
        XCTAssertEqual(before.contentHash,after.contentHash);XCTAssertEqual(before.snapshot.xattrHashes,after.snapshot.xattrHashes)
        XCTAssertEqual(before.snapshot.permissions,after.snapshot.permissions);XCTAssertEqual(before.snapshot.aclText,after.snapshot.aclText)
    }
    func testReset1904OrExplicitUnsupported() throws {
        for both in [false,true] {
            let stage=try ownedStage("paris.jpg"),date=try utc("1904-01-01T00:00:00Z")
            let result=try FileDateWriter().apply(.init(creationDate:date,modificationDate:both ? date:nil),to:stage)
            XCTAssertEqual(result.snapshot.creationDate,date)
            if both {XCTAssertEqual(result.snapshot.modificationDate,date)}
        }
    }
    func testOutOfRangeDateDoesNotTouchStage() throws {
        let stage=try ownedStage("paris.jpg"),before=try FileIdentityReader().fingerprint(at:stage)
        XCTAssertThrowsError(try FileDateWriter().apply(.init(creationDate:Date(timeIntervalSince1970:Double.greatestFiniteMagnitude)),to:stage))
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:stage))
    }
    func testDatesWrittenLastAndReadBack() async throws {
        let stage=try ownedStage("paris.jpg"),date=try utc("2020-02-03T04:05:06Z").addingTimeInterval(0.125),tag=TagID(rawValue:"ExifIFD:UserComment")!
        let dates=DateMutation(creationDate:date,modificationDate:date,embeddedDate:nil,embeddedOffsetSeconds:0,removeEmbeddedDates:false,notes:[])
        let mutation=MutationPlan(dates:dates,tags:[.set(tag,.string("dates written last"))],profile:.init(identifier:"JPEG",family:.photo),allowedMetadataChanges:.init(tags:[tag.rawValue]))
        let paths=try RuntimeLocator().locate(in:testApp),result=try await AttributeMutationDriver(paths:paths).apply(mutation,to:stage),after=try FileIdentityReader().fingerprint(at:stage)
        XCTAssertEqual(after.snapshot.creationDate,date);XCTAssertEqual(after.snapshot.modificationDate,date)
        XCTAssertEqual(result.contentHash,after.contentHash);XCTAssertNotEqual(result.integrityValidator,"sha256-v1")
    }
    func testIndependentOriginalTargetShifts() throws {
        let snapshot=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        var policy=DatePolicy();policy.source = .automaticCapture;policy.targets = [.creation,.modification,.capture];policy.shiftSeconds=7200;policy.shiftOriginalTargets=true
        let resolution=CaptureDateResolver.instant(try utc("2024-01-02T01:04:05Z"),source:"capture")
        let change=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:snapshot,sequenceIndex:0)
        XCTAssertEqual(change.creationDate,snapshot.creationDate.addingTimeInterval(7200))
        XCTAssertEqual(change.modificationDate,snapshot.modificationDate.addingTimeInterval(7200))
        XCTAssertEqual(change.embeddedDate,resolution.instant.addingTimeInterval(7200))
    }
}
