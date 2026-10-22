import XCTest
import Foundation

class CoreTestCase: XCTestCase {
    var workspace: URL!
    var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    var testApp: URL {
        if let path = ProcessInfo.processInfo.environment["RESTOREGPSTIME_TEST_APP"] { return URL(fileURLWithPath: path) }
        return repository.appendingPathComponent("work/test-bundles/arm64-standard/RestoreGPSTime.app")
    }
    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("RestoreGPSTimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let workspace { try FileManager.default.removeItem(at: workspace) }
    }
    func fixture(_ id: String) throws -> URL {
        let url = repository.appendingPathComponent("Tests/Fixtures/\(id)")
        guard FileManager.default.fileExists(atPath: url.path) else { throw NSError(domain: "FixtureMissing", code: 1) }
        return url
    }
    func utc(_ text: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: text) else { throw NSError(domain: "InvalidTestDate", code: 1) }
        return date
    }
}
