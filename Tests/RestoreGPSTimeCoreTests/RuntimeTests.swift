import XCTest
import Foundation
@testable import RestoreGPSTimeCore

final class RuntimeTests: CoreTestCase {
    func testLiteralArgumentsAreNotShellCommands() async throws {
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "$(touch never);\n-thing"], environment: [:], timeout: 3)
        XCTAssertEqual(result.text, "$(touch never);\n-thing")
    }
    func testBundleRuntimeWorksWithoutSystemPerl() async throws {
        let identity = try await RuntimeProbe().inspect(paths: RuntimeLocator().locate(in: testApp))
        XCTAssertEqual(identity.exifToolVersion, "13.59")
        XCTAssertEqual(identity.perlVersion, "5.44.0")
        XCTAssertFalse(identity.loadedPaths.isEmpty)
        XCTAssertFalse(identity.loadedPaths.contains { $0.hasPrefix("/opt/homebrew") || $0.hasPrefix("/usr/lib") })
    }
    func testHostileEnvironmentIsIgnored() async throws {
        let old = getenv("PERL5OPT").map { String(cString: $0) }
        setenv("PERL5OPT", "-MDefinitelyNotAnInstalledModule", 1)
        defer { if let old { setenv("PERL5OPT", old, 1) } else { unsetenv("PERL5OPT") } }
        let identity = try await RuntimeProbe().inspect(paths: RuntimeLocator().locate(in: testApp))
        XCTAssertEqual(identity.exifToolVersion, "13.59")
    }
    func testUnicodeRelocation() async throws {
        let moved = workspace.appendingPathComponent("Images été 東京/RestoreGPSTime.app")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: testApp.path) { try FileManager.default.copyItem(at: testApp, to: moved) }
        let identity = try await RuntimeProbe().inspect(paths: RuntimeLocator().locate(in: moved))
        XCTAssertEqual(identity.perlVersion, "5.44.0")
        XCTAssertTrue(identity.loadedPaths.allSatisfy { $0.hasPrefix(moved.path) })
    }
    func testStderrFloodDoesNotDeadlock() async throws {
        let paths = try RuntimeLocator().locate(in: testApp)
        do {
            _ = try await ProcessRunner().run(executable: paths.perl, arguments: ["-e", "print STDERR 'x' x 4000000; print 'done'"], environment: [:], timeout: 10)
            XCTFail("Output overflow must stop with a bounded diagnostic")
        } catch let error as RestoreError { XCTAssertEqual(error.code, .outputLimit) }
    }
    func testTimeoutAndCancellationStopChild() async throws {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], environment: [:], timeout: 0.1)
            XCTFail("Timeout was ignored")
        } catch let error as RestoreError { XCTAssertEqual(error.code, .timeout) }
        let task = Task { try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], environment: [:], timeout: 30) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation was ignored") }
        catch let error as RestoreError { XCTAssertEqual(error.code, .cancelled) }
    }
    func testArchitectureAndDeploymentTarget() async throws {
        let expected=ProcessInfo.processInfo.environment["RESTOREGPSTIME_TEST_ARCH"] ?? "arm64"
        let entries=FileManager.default.enumerator(at:testApp.appendingPathComponent("Contents"),includingPropertiesForKeys:[.isRegularFileKey])!
        var nativeCount=0
        for case let executable as URL in entries {
            guard (try? executable.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else { continue }
            let handle=try FileHandle(forReadingFrom:executable)
            let magic=try handle.read(upToCount:4) ?? Data();try handle.close()
            guard [Data([0xcf,0xfa,0xed,0xfe]),Data([0xca,0xfe,0xba,0xbe])].contains(magic) else { continue }
            nativeCount+=1
            let result=try await ProcessRunner().run(executable:URL(fileURLWithPath:"/usr/bin/lipo"),arguments:["-archs",executable.path],environment:[:],timeout:5)
            XCTAssertEqual(result.text.trimmingCharacters(in:.whitespacesAndNewlines),expected,executable.path)
            let build=try await ProcessRunner().run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["vtool","-show-build",executable.path],environment:["PATH":"/usr/bin:/bin"],timeout:5)
            XCTAssertTrue(build.text.contains("minos 13.0"),executable.path+"\n"+build.text)
        }
        XCTAssertGreaterThan(nativeCount,1,"The bundled native modules were not inspected")
    }
}
