import XCTest
@testable import RestoreGPSTimeCore

final class AutomaticTimezoneTests:CoreTestCase {
    private func document(_ date:String,zone:String?=nil,gps:Bool=true,distance:Double=1) -> MetadataDocument {
        var tags:[String:TagValue]=["ExifIFD:DateTimeOriginal":.string(date)]
        if gps {tags["GPS:GPSLatitude"] = .real(48.8566);tags["GPS:GPSLongitude"] = .real(2.3522)}
        if let zone {tags["ExifTool:GeolocationTimeZone"] = .string(zone);tags["ExifTool:GeolocationDistance"] = .real(distance);tags["ExifTool:GeolocationCity"] = .string("Generated test city")}
        return .init(tags:tags,profile:.init(identifier:"JPEG",family:.photo))
    }
    private func resolve(_ doc:MetadataDocument,fallback:String?=nil) throws -> DateResolution {
        var policy=DatePolicy();policy.automaticTimeZone=true;policy.timeZoneID=fallback
        return try CaptureDateResolver().resolve(document:doc,snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:policy)
    }
    func testGPSZoneUsesCaptureDateIncludingDaylightSavingAndDifferentCountries() throws {
        let cases=[("2024:01:15 12:00:00","Europe/Paris","2024-01-15T11:00:00Z"),("2024:07:15 12:00:00","Europe/Paris","2024-07-15T10:00:00Z"),("2024:07:15 12:00:00","America/New_York","2024-07-15T16:00:00Z"),("2024:01:15 12:00:00","Asia/Tokyo","2024-01-15T03:00:00Z")]
        for (date,zone,expected) in cases {
            let result=try resolve(document(date,zone:zone),fallback:"UTC")
            XCTAssertEqual(result.instant,try utc(expected));XCTAssertTrue(result.interpretation.contains("GPS"));XCTAssertFalse(result.warnings.isEmpty)
        }
    }
    func testEmbeddedOffsetWinsOverGPSAndBatchFallback() throws {
        let result=try resolve(document("2024:07:15 12:00:00+09:00",zone:"America/New_York"),fallback:"Europe/Paris")
        XCTAssertEqual(result.instant,try utc("2024-07-15T03:00:00Z"));XCTAssertFalse(result.interpretation.contains("GPS"))
    }
    func testOneBatchFallbackHandlesMissingGPSAndRejectsUnprovedOrDistantZone() throws {
        for doc in [document("2024:01:15 12:00:00",gps:false),document("2024:01:15 12:00:00",zone:"Asia/Tokyo",gps:false),document("2024:01:15 12:00:00",zone:"Asia/Tokyo",distance:26),document("2024:01:15 12:00:00",zone:"Invalid/Zone")] {
            let result=try resolve(doc,fallback:"Europe/Paris")
            XCTAssertEqual(result.instant,try utc("2024-01-15T11:00:00Z"));XCTAssertTrue(result.interpretation.contains("Batch fallback"));XCTAssertFalse(result.warnings.isEmpty)
        }
    }
    func testMissingGPSAndFallbackRequestsOneBatchChoice() throws {
        XCTAssertThrowsError(try resolve(document("2024:01:15 12:00:00",gps:false))) {error in
            XCTAssertEqual((error as? RestoreError)?.code,.timezoneRequired);XCTAssertTrue(error.localizedDescription.contains("batch"))
        }
    }
    func testStrictModeAndOldPoliciesStillRequireTheExplicitZone() throws {
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(DatePolicy())) as? [String:Any])
        object.removeValue(forKey:"automaticTimeZone")
        let policy=try JSONDecoder().decode(DatePolicy.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNotEqual(policy.automaticTimeZone,true)
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:document("2024:01:15 12:00:00",zone:"Europe/Paris"),snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:policy))
    }
    func testRealPhotoWithoutGPSUsesOneBatchFallbackWithoutGeolocationError() async throws {
        let photo=workspace.appendingPathComponent("No GPS.jpg")
        try FileManager.default.copyItem(at:fixture("paris.jpg"),to:photo)
        let paths=RuntimePaths(appBundle:testApp)
        let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(["-overwrite_original","-GPS:all=","-ExifIFD:OffsetTimeOriginal=","-ExifIFD:OffsetTimeDigitized=","--",photo.path]),environment:paths.environment,timeout:60)
        XCTAssertEqual(result.exitStatus,0)
        let snapshot=try FileIdentityReader().snapshot(at:photo)
        let document=try await MetadataReader(paths:paths).read(snapshot:snapshot)
        XCTAssertNil(document.tags["ExifTool:GeolocationTimeZone"])
        XCTAssertTrue(document.diagnostics.isEmpty,document.diagnostics.joined(separator:"; "))
        let resolution=try resolve(document,fallback:"Europe/Paris")
        XCTAssertTrue(resolution.interpretation.contains("Batch fallback"))
    }
    func testRealBundledReaderIncludesOfflineZoneInSingleAndBatchResults() async throws {
        let snapshot=try FileIdentityReader().snapshot(at:fixture("paris.jpg")),reader=MetadataReader(paths:.init(appBundle:testApp))
        let single=try await reader.read(snapshot:snapshot),batch=try await reader.readBatch(snapshots:[snapshot])
        XCTAssertEqual(single.tags["ExifTool:GeolocationTimeZone"]?.text,"Europe/Paris")
        XCTAssertEqual(batch.first?.tags["ExifTool:GeolocationTimeZone"]?.text,"Europe/Paris")
    }
}
