import XCTest
@testable import RestoreGPSTimeCore

final class CaptureDateTests:CoreTestCase {
    func testExplicitOffsetWins() throws {
        let document=MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05"),"ExifIFD:OffsetTimeOriginal":.string("+02:00"),"ExifIFD:SubSecTimeOriginal":.string("123")])
        var policy=DatePolicy();policy.timeZoneID="Pacific/Honolulu"
        let date=try CaptureDateResolver().resolve(document:document,snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:policy)
        XCTAssertEqual(date.instant.timeIntervalSince1970,try utc("2024-01-02T01:04:05Z").timeIntervalSince1970+0.123,accuracy:0.000001)
        XCTAssertEqual(date.source,"ExifIFD:DateTimeOriginal")
        XCTAssertEqual(date.fractionalPrecision,3)
    }
    func testUnzonedRequiresSelection() throws {
        let doc=MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05")])
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:doc,snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:DatePolicy())) { XCTAssertEqual(($0 as? RestoreError)?.code,.timezoneRequired) }
    }
    func testQuickTimeIntegerNeedsInterpretation() throws {
        let doc=MetadataDocument(tags:["QuickTime:CreateDate":.string("2024:01:02 03:04:05")],profile:.init(identifier:"MOV",family:.video))
        let file=try FileIdentityReader().snapshot(at:fixture("paris.mov"))
        var policy=DatePolicy()
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:doc,snapshot:file,policy:policy))
        policy.quickTime = .utc
        XCTAssertEqual(try CaptureDateResolver().resolve(document:doc,snapshot:file,policy:policy).instant,try utc("2024-01-02T03:04:05Z"))
        policy.quickTime = .cameraLocal;policy.timeZoneID="Pacific/Honolulu"
        XCTAssertEqual(try CaptureDateResolver().resolve(document:doc,snapshot:file,policy:policy).instant,try utc("2024-01-02T13:04:05Z"))
    }
    func testGeneratedImageAndMovieDateSources() async throws {
        let reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        for name in ["paris.jpg","paris.heic","paris.mov"] {
            let snapshot=try FileIdentityReader().snapshot(at:fixture(name))
            let document=try await reader.read(snapshot:snapshot)
            let date=try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:DatePolicy())
            let fraction=name.hasSuffix("mov") ? 0.0:0.123
            XCTAssertEqual(date.instant.timeIntervalSince1970,try utc("2024-01-02T01:04:05Z").timeIntervalSince1970+fraction,accuracy:0.000001,name)
        }
    }
}
