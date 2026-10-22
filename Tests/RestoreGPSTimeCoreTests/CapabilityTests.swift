import XCTest
@testable import RestoreGPSTimeCore

final class CapabilityTests: CoreTestCase {
    func testExtensionDoesNotDecideWriteSupport() throws {
        let url=workspace.appendingPathComponent("pretending.jpg")
        try Data("mkv".utf8).write(to:url)
        let snapshot=try FileIdentityReader().snapshot(at:url)
        let document=MetadataDocument(tags:[:],profile:.init(identifier:"MKV",family:.video))
        XCTAssertFalse(CapabilityRegistry().decision(for:.embeddedWrite,document:document,snapshot:snapshot).isSupported)
    }
    func testReadOnlyVideoStillAllowsDateRestore() throws {
        let url=workspace.appendingPathComponent("movie.mkv");try Data().write(to:url)
        let snapshot=try FileIdentityReader().snapshot(at:url)
        let document=MetadataDocument(tags:[:],profile:.init(identifier:"MKV",family:.video))
        XCTAssertTrue(CapabilityRegistry().decision(for:.filesystemDates,document:document,snapshot:snapshot).isSupported)
        XCTAssertFalse(CapabilityRegistry().decision(for:.stripMetadata,document:document,snapshot:snapshot).isSupported)
    }
}
