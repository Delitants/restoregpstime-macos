import XCTest
@testable import RestoreGPSTimeCore

final class DependencyIdentityTests:CoreTestCase {
    private func runtime() throws -> RuntimePaths {
        let paths=RuntimePaths(appBundle:workspace.appendingPathComponent("RestoreGPSTime.app"))
        for (url,text) in [(paths.perl,"synthetic interpreter"),(paths.exifTool,"synthetic helper"),(paths.exifToolRoot.appendingPathComponent("lib/Module.pm"),"module"),(paths.database,"synthetic place database"),(paths.runtimeRoot.appendingPathComponent("lib/perl5/Config.pm"),"config"),(paths.nativeModules.appendingPathComponent("Fake.bundle"),"synthetic native module"),(paths.appBundle.appendingPathComponent("Contents/MacOS/RestoreGPSTime"),"synthetic app"),(paths.appBundle.appendingPathComponent("Contents/Resources/container-capabilities.json"),"capabilities"),(paths.appBundle.appendingPathComponent("Contents/Resources/writable-tags.json"),"tags")] {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url)
        }
        return paths
    }
    func testActualDependencyBytesDetermineIdentity() async throws {
        let paths=try runtime(),provider=DependencyIdentityProvider(paths:paths),a=try await provider.observe()
        try Data("changed helper".utf8).write(to:paths.exifTool);let b=try await provider.observe()
        XCTAssertNotEqual(a.engineHash,b.engineHash);XCTAssertEqual(a.databaseHash,b.databaseHash);XCTAssertEqual(a.capabilityHash,b.capabilityHash)
        try Data("changed database".utf8).write(to:paths.database);let c=try await provider.observe()
        XCTAssertEqual(b.engineHash,c.engineHash);XCTAssertNotEqual(b.databaseHash,c.databaseHash)
        try Data("changed tags".utf8).write(to:paths.appBundle.appendingPathComponent("Contents/Resources/writable-tags.json"));let d=try await provider.observe()
        XCTAssertEqual(c.engineHash,d.engineHash);XCTAssertNotEqual(c.capabilityHash,d.capabilityHash)
    }
    func testMissingPolicyOrSymlinkEngineFailsClosed() async throws {
        let paths=try runtime(),provider=DependencyIdentityProvider(paths:paths)
        let policy=paths.appBundle.appendingPathComponent("Contents/Resources/writable-tags.json")
        try FileManager.default.removeItem(at:policy)
        do {_ = try await provider.observe();XCTFail("Missing policy must not produce a permissive identity")} catch is RestoreError {}
        try Data("restored policy".utf8).write(to:policy)
        let module=paths.exifToolRoot.appendingPathComponent("lib/Module.pm");try FileManager.default.removeItem(at:module)
        try FileManager.default.createSymbolicLink(at:module,withDestinationURL:paths.database)
        do {_ = try await provider.observe();XCTFail("Runtime symlinks are outside the qualified bundle layout")} catch is RestoreError {}
    }
}
