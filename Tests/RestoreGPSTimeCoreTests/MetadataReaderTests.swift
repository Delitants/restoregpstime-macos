import XCTest
@testable import RestoreGPSTimeCore

final class MetadataReaderTests: CoreTestCase {
    func testDuplicateGroupsAreRetained() throws {
        let data=Data("[{\"ExifIFD:CreateDate\":\"2024:01:01 01:02:03\",\"QuickTime:CreateDate\":\"2020:02:03 04:05:06\",\"File:FileType\":\"MOV\"}]".utf8)
        let document=try MetadataDecoder().decode(data)
        XCTAssertEqual(document.tags["ExifIFD:CreateDate"]?.text,"2024:01:01 01:02:03")
        XCTAssertEqual(document.tags["QuickTime:CreateDate"]?.text,"2020:02:03 04:05:06")
        XCTAssertEqual(document.profile.family,.video)
    }
    func testNewlineAndLeadingDashPaths() async throws {
        let url=workspace.appendingPathComponent("-photo\n$(not-a-command).jpg")
        try FileManager.default.copyItem(at:fixture("paris.jpg"),to:url)
        let before=try FileIdentityReader().fingerprint(at:url)
        let reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        let document=try await reader.read(snapshot:before.snapshot)
        XCTAssertEqual(document.profile.identifier,"JPEG")
        XCTAssertEqual(document.tags["ExifIFD:DateTimeOriginal"]?.text,"2024:01:02 03:04:05")
        XCTAssertEqual(try FileIdentityReader().fingerprint(at:url),before)
    }
    func testMalformedJSONHasAnExplicitError() {
        XCTAssertThrowsError(try MetadataDecoder().decode(Data("[bad".utf8)))
    }
    func testBoundedParallelInspection() async throws {
        let reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        let snapshot=try FileIdentityReader().snapshot(at:fixture("paris.jpg"))
        try await withThrowingTaskGroup(of:String.self) { group in
            for _ in 0..<12 { group.addTask { try await reader.read(snapshot:snapshot).profile.identifier } }
            for try await format in group { XCTAssertEqual(format,"JPEG") }
        }
        let metrics=await reader.metrics()
        XCTAssertEqual(metrics.completed,12)
        XCTAssertEqual(metrics.active,0)
        XCTAssertGreaterThan(metrics.maximumActive,0)
        XCTAssertLessThanOrEqual(metrics.maximumActive,2)
    }
}
