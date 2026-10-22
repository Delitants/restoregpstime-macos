import XCTest
@testable import RestoreGPSTimeCore

final class MetadataProvenanceTests:MetadataStageTestCase {
    private func decode(_ fields:[String:Any]) throws -> MetadataDocument {try MetadataDecoder().decode(JSONSerialization.data(withJSONObject:[fields]))}
    func testReadBackRequiresExactNanosecondDateAndZone() {
        XCTAssertFalse(ExifToolWriter.matchesReadBack(.string("2024:01:02 03:04:05.123456788+02:00"),.string("2024:01:02 03:04:05.123456789+02:00"),type:"date"))
        XCTAssertTrue(ExifToolWriter.matchesReadBack(.string("2024:01:02 03:04:05.123456789+02:00"),.string("2024:01:02 03:04:05.123456789+02:00"),type:"date"))
        XCTAssertFalse(ExifToolWriter.matchesReadBack(.string("2024:01:02 03:04:05.123456789Z"),.string("2024:01:02 03:04:05.123456789+02:00"),type:"date"))
    }
    func testSpecificCopySelectionCannotInventAnAbsentCopy() throws {
        let single=try decode(["ExifIFD:DateTimeOriginal":"2024:01:02 03:04:05"])
        XCTAssertNil(try single.readValue("ExifIFD:Copy99:DateTimeOriginal"))
        XCTAssertEqual(try single.readValue("ExifIFD:Copy0:DateTimeOriginal"),.string("2024:01:02 03:04:05"))
        let aliased=try decode(["GPS:Copy1:GPSLatitude":48.8566])
        XCTAssertNil(try aliased.readValue("GPS:Copy0:GPSLatitude"))
    }
    func testTrackHandlerCopiesRemainProtectedAsACompleteMultiset() throws {
        let before=try decode(["File:FileType":"MOV","Track1:HandlerClass":"dhlr","Track1:Copy1:HandlerClass":"mhlr","Track1:Copy1:HandlerType":"vide","Track1:Copy2:HandlerType":"alis"])
        let same=try decode(["File:FileType":"MOV","Track1:HandlerClass":"dhlr","Track1:Copy2:HandlerClass":"mhlr","Track1:Copy3:HandlerType":"vide","Track1:Copy4:HandlerType":"alis"])
        XCTAssertNoThrow(try MetadataMutationDriver.verifyDiff(before:before,after:same,tags:[],stripping:false))
        let changed=try decode(["File:FileType":"MOV","Track1:HandlerClass":"dhlr","Track1:Copy1:HandlerClass":"mhlr","Track1:Copy1:HandlerType":"soun","Track1:Copy2:HandlerType":"alis"])
        XCTAssertThrowsError(try MetadataMutationDriver.verifyDiff(before:before,after:changed,tags:[],stripping:false))
    }
    func testConflictingCaptureCopiesDoNotSelectOneSilently() throws {
        let document=try decode(["File:FileType":"JPEG","ExifIFD:DateTimeOriginal":"2024:01:02 03:04:05","ExifIFD:Copy1:DateTimeOriginal":"2025:01:02 03:04:05","ExifIFD:OffsetTimeOriginal":"+02:00"]),snapshot=try FileIdentityReader().snapshot(at:ownedStage("paris.jpg"))
        XCTAssertNil(document.tags["ExifIFD:DateTimeOriginal"])
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy())) {XCTAssertEqual(($0 as? RestoreError)?.code,.conflict)}
    }
    func testConflictingCompanionsDoNotBecomeAnInventedInstant() throws {
        let document=try decode(["File:FileType":"JPEG","ExifIFD:DateTimeOriginal":"2024:01:02 03:04:05","ExifIFD:OffsetTimeOriginal":"+02:00","ExifIFD:Copy1:OffsetTimeOriginal":"+03:00"]),snapshot=try FileIdentityReader().snapshot(at:ownedStage("paris.jpg"))
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy())) {XCTAssertEqual(($0 as? RestoreError)?.code,.conflict)}
    }
    func testSingletonCopyQualifiedGPSNormalizesAndConflictsReject() throws {
        let single=try decode(["GPS:Copy1:GPSLatitude":48.8566,"GPS:Copy1:GPSLongitude":2.3522])
        let coordinates=try MetadataCoordinates.read(single);XCTAssertEqual(coordinates.0,48.8566);XCTAssertEqual(coordinates.1,2.3522)
        let conflicting=try decode(["GPS:GPSLatitude":48.8566,"GPS:Copy1:GPSLatitude":49.0,"GPS:GPSLongitude":2.3522])
        XCTAssertThrowsError(try MetadataCoordinates.read(conflicting)) {XCTAssertEqual(($0 as? RestoreError)?.code,.conflict)}
    }
    func testEqualCopiesReadConsistentlyAndGeolocationDocGroupsRemain() throws {
        let document=try decode(["File:FileType":"JPEG","ExifIFD:DateTimeOriginal":"2024:01:02 03:04:05","ExifIFD:Copy1:DateTimeOriginal":"2024:01:02 03:04:05","ExifIFD:OffsetTimeOriginal":"+02:00"]),snapshot=try FileIdentityReader().snapshot(at:ownedStage("paris.jpg"))
        let value=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy())
        XCTAssertEqual(value.instant,try utc("2024-01-02T01:04:05Z"))
        let locations=try decode(["Doc1:ExifTool:GeolocationCity":"Paris","Doc2:ExifTool:GeolocationCity":"Versailles"])
        XCTAssertEqual(locations.tags["Doc1:ExifTool:GeolocationCity"],.string("Paris"));XCTAssertEqual(locations.tags["Doc2:ExifTool:GeolocationCity"],.string("Versailles"))
    }
    func testNativeDuplicateEXIFIsRetainedAndEmbeddedWritesBlock() async throws {
        let stage=try ownedStage("paris.jpg"),bytes=try Data(contentsOf:stage)
        var offset=2,segment:Data?
        while offset+4<bytes.count {
            guard bytes[offset]==0xff else {throw RestoreError(.malformedMetadata,"Fixture marker")}
            let marker=bytes[offset+1];if marker==0xda || marker==0xd9 {break}
            let length=Int(bytes[offset+2])<<8|Int(bytes[offset+3]),end=offset+2+length
            guard end<=bytes.count else {throw RestoreError(.malformedMetadata,"Fixture extent")}
            if marker==0xe1,bytes[offset+4..<min(end,offset+10)]==Data("Exif\0\0".utf8) {segment=Data(bytes[offset..<end]);break}
            offset=end
        }
        var extra=try XCTUnwrap(segment),original=Data("2024:01:02 03:04:05".utf8),replacement=Data("2025:01:02 03:04:05".utf8)
        let range=try XCTUnwrap(extra.range(of:original));extra.replaceSubrange(range,with:replacement)
        var duplicate=Data(bytes[..<offset]);duplicate.append(extra);duplicate.append(bytes[offset...]);try duplicate.write(to:stage,options:.atomic);try StageOwnership.shared.refresh(stage)
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths),snapshot=try FileIdentityReader().snapshot(at:stage),document=try await reader.read(snapshot:snapshot)
        XCTAssertNil(document.tags["ExifIFD:DateTimeOriginal"])
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy()))
        var request=OperationRequest();request.tags=[.set(TagID(rawValue:"XMP-dc:Description")!,.string("Do not rewrite an unqualified repeated layout"))]
        var options=BatchOptions();options.outputRoot=workspace.appendingPathComponent("Output");options.recoveryRoot=workspace.appendingPathComponent("Recovery")
        let plan=try await BatchPlanner(dependencies:.init(engineHash:"test",databaseHash:"test",capabilityHash:"test"),reader:reader).preview(items:[.init(snapshot:snapshot,metadata:document)],request:request,options:options)
        XCTAssertEqual(plan.groups.first?.eligibility,.blocked)
        XCTAssertEqual(try Data(contentsOf:stage),duplicate)
    }
}
