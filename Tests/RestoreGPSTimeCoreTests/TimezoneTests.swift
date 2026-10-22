import XCTest
@testable import RestoreGPSTimeCore

final class TimezoneTests:CoreTestCase {
    private func resolve(_ text:String,policy:DatePolicy) throws -> DateResolution {
        try CaptureDateResolver().resolve(document:.init(tags:["ExifIFD:DateTimeOriginal":.string(text)]),snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:policy)
    }
    func testFallBackNeedsOccurrenceChoice() throws {
        var policy=DatePolicy();policy.timeZoneID="America/New_York"
        XCTAssertThrowsError(try resolve("2024:11:03 01:30:00",policy:policy)) { XCTAssertEqual(($0 as? RestoreError)?.code,.ambiguousTime) }
        policy.dstChoice = .earlier
        XCTAssertEqual(try resolve("2024:11:03 01:30:00",policy:policy).instant,try utc("2024-11-03T05:30:00Z"))
        policy.dstChoice = .later
        XCTAssertEqual(try resolve("2024:11:03 01:30:00",policy:policy).instant,try utc("2024-11-03T06:30:00Z"))
    }
    func testSpringGapBlocks() throws {
        var policy=DatePolicy();policy.timeZoneID="America/New_York"
        XCTAssertThrowsError(try resolve("2024:03:10 02:30:00",policy:policy)) { XCTAssertEqual(($0 as? RestoreError)?.code,.nonexistentTime) }
    }
    func testHostTimezoneDoesNotChangeResolution() throws {
        var policy=DatePolicy();policy.timeZoneID="Europe/Paris"
        let old=getenv("TZ").map {String(cString:$0)}
        defer { if let old {setenv("TZ",old,1)} else {unsetenv("TZ")} }
        setenv("TZ","UTC",1);let a=try resolve("2024:01:02 03:04:05",policy:policy)
        setenv("TZ","Pacific/Honolulu",1);let b=try resolve("2024:01:02 03:04:05",policy:policy)
        XCTAssertEqual(a,b)
        XCTAssertEqual(a.instant,try utc("2024-01-02T02:04:05Z"))
    }
}
