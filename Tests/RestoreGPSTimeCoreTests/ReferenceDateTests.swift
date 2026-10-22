import XCTest
@testable import RestoreGPSTimeCore

final class ReferenceDateTests:CoreTestCase {
    func testCurrentTimeIsFrozen() async throws {
        let now=try utc("2024-03-04T05:06:07Z")
        let context=ReferenceDateContext(clock:FixedClock(now))
        let file=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        let result=try await ReferenceDateResolver().resolve(source:.current,snapshot:file,context:context)
        XCTAssertEqual(result.instant,now)
    }
    func testFilenameRejectsInvalidCalendarDate() throws {
        XCTAssertThrowsError(try FilenameDateParser().parse(filename:"IMG_20240230_030405.jpg",pattern:"yyyyMMdd_HHmmss"))
        XCTAssertEqual(try FilenameDateParser().parse(filename:"IMG_20240102_030405.jpg",pattern:"yyyyMMdd_HHmmss"),"2024:01:02 03:04:05")
    }
    func testReferenceHierarchyAmbiguity() async throws {
        let input=workspace.appendingPathComponent("input"),ref=workspace.appendingPathComponent("reference")
        try FileManager.default.createDirectory(at:input,withIntermediateDirectories:true)
        try Data().write(to:input.appendingPathComponent("photo.jpg"))
        for folder in ["a","b"] { let dir=ref.appendingPathComponent(folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try Data().write(to:dir.appendingPathComponent("photo.jpg")) }
        var context=ReferenceDateContext();context.referenceRoot=ref;context.inputRoot=input;context.allowBasenameFallback=true
        let file=try FileIdentityReader().snapshot(at:input.appendingPathComponent("photo.jpg"))
        do { _=try await ReferenceDateResolver().resolve(source:.referenceFile(.creation),snapshot:file,context:context);XCTFail("Ambiguous reference names must block") }
        catch let error as RestoreError { XCTAssertEqual(error.code,.conflict) }
    }
    func testResetValueAndCompanionDate() async throws {
        let file=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        let reset=try await ReferenceDateResolver().resolve(source:.reset,snapshot:file,context:.init())
        XCTAssertEqual(reset.instant,try utc("1904-01-01T00:00:00Z"))
        var policy=DatePolicy();policy.targets=[.creation,.modification]
        let mutation=try DateMutationPlanner().plan(resolution:reset,policy:policy,snapshot:file,sequenceIndex:0)
        XCTAssertEqual(mutation.creationDate,reset.instant);XCTAssertEqual(mutation.modificationDate,reset.instant)
        policy.shiftSeconds=86400
        let shifted=try DateMutationPlanner().plan(resolution:reset,policy:policy,snapshot:file,sequenceIndex:0)
        XCTAssertEqual(shifted.creationDate,try utc("1904-01-02T00:00:00Z"))
    }
    func testSequenceAndSelectedTargets() throws {
        let file=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        var policy=DatePolicy();policy.sequenceStart=try utc("2024-01-01T00:00:00Z");policy.sequenceStepSeconds=2;policy.shiftSeconds=1;policy.targets = .capture
        let mutation=try DateMutationPlanner().plan(resolution:CaptureDateResolver.instant(file.creationDate,source:"source"),policy:policy,snapshot:file,sequenceIndex:3)
        XCTAssertEqual(mutation.embeddedDate,try utc("2024-01-01T00:00:07Z"))
        XCTAssertNil(mutation.creationDate);XCTAssertNil(mutation.modificationDate)
    }
    func testCompanionNormalizationIsExplicit() throws {
        let file=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        let resolution=CaptureDateResolver.instant(file.modificationDate.addingTimeInterval(3600),source:"future")
        var policy=DatePolicy();policy.targets = .creation;policy.requiresMonotonicFileDates=true
        XCTAssertThrowsError(try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:file,sequenceIndex:0))
        policy.normalizeCompanionDate=true
        let mutation=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:file,sequenceIndex:0)
        XCTAssertEqual(mutation.creationDate,mutation.modificationDate);XCTAssertFalse(mutation.notes.isEmpty)
    }
}
