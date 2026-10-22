import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class DiscoveryTests: CoreTestCase {
    func testExplicitRootContentsWithoutSubfolderRecursion() async throws {
        let nested=workspace.appendingPathComponent("nested");try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:false)
        try Data("root".utf8).write(to:workspace.appendingPathComponent("one.jpg"));try Data("nested".utf8).write(to:nested.appendingPathComponent("two.jpg"))
        var options=DiscoveryOptions();options.includeFolders=false;options.enumerateRootContents=true
        let result=await SourceInventory().scan(urls:[workspace],options:options)
        XCTAssertEqual(result.snapshots.map {$0.url.lastPathComponent},["one.jpg"])
        options.recursive=true;let recursive=await SourceInventory().scan(urls:[workspace],options:options)
        XCTAssertEqual(Set(recursive.snapshots.map {$0.url.lastPathComponent}),["one.jpg","two.jpg"])
    }
    func testPrivateTransactionDirectoryNeverBecomesInput() async throws {
        let privateRoot=workspace.appendingPathComponent(".RestoreGPSTime-owned-evidence");try FileManager.default.createDirectory(at:privateRoot,withIntermediateDirectories:false)
        try Data("retained original".utf8).write(to:privateRoot.appendingPathComponent("old.jpg"))
        var options=DiscoveryOptions();options.recursive=true;options.includeFolders=false;options.includeHidden=true
        let result=await SourceInventory().scan(urls:[privateRoot],options:options)
        XCTAssertTrue(result.snapshots.isEmpty);XCTAssertEqual(result.excluded.count,1)
    }
    func testSymlinkHardlinkPackageAndPlaceholderRules() async throws {
        let file = workspace.appendingPathComponent("original.jpg")
        try Data("test-data".utf8).write(to:file)
        let linked = workspace.appendingPathComponent("linked.jpg")
        let symlink = workspace.appendingPathComponent("symbol.jpg")
        try FileManager.default.linkItem(at:file,to:linked)
        try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:file)
        let package = workspace.appendingPathComponent("Other.app")
        try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
        try Data("private".utf8).write(to:package.appendingPathComponent("inside.jpg"))
        var options = DiscoveryOptions(); options.recursive = true; options.includeFolders = false
        let result = await SourceInventory().scan(urls:[workspace],options:options)
        XCTAssertEqual(result.snapshots.count,1)
        XCTAssertEqual(result.snapshots.first?.id.linkCount,2)
        let report=result.excluded.map { "\($0.url.absoluteString): \($0.reason)" }.joined(separator:"\n")
        XCTAssertTrue(result.excluded.contains { $0.url.standardizedFileURL.path == symlink.standardizedFileURL.path },report)
        XCTAssertTrue(result.excluded.contains { $0.url.standardizedFileURL.path == package.standardizedFileURL.path },report)
    }
    func testOutputInsideInputIsExcluded() async throws {
        let output = workspace.appendingPathComponent("output")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try Data("source".utf8).write(to:workspace.appendingPathComponent("source.jpg"))
        try Data("output".utf8).write(to:output.appendingPathComponent("copy.jpg"))
        var options=DiscoveryOptions();options.recursive=true;options.includeFolders=false;options.excludedRoots=[output]
        let result=await SourceInventory().scan(urls:[workspace],options:options)
        XCTAssertEqual(result.snapshots.map { $0.url.lastPathComponent },["source.jpg"])
    }
    func testExplicitlySelectedSymlinkIsNotFollowed() async throws {
        let target=workspace.appendingPathComponent("target.jpg")
        try Data("unchanged".utf8).write(to:target)
        let link=workspace.appendingPathComponent("selected.jpg")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        let result=await SourceInventory().scan(urls:[link],options:DiscoveryOptions())
        XCTAssertTrue(result.snapshots.isEmpty)
        XCTAssertEqual(result.excluded.count,1)
    }
    func testStreamingFingerprintAndInspectionPreserveSources() throws {
        let file=workspace.appendingPathComponent("empty")
        try Data().write(to:file)
        let reader=FileIdentityReader()
        let first=try reader.fingerprint(at:file)
        XCTAssertEqual(first.contentHash,"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let second=try reader.fingerprint(at:file)
        XCTAssertEqual(first,second)
        try Data("changed".utf8).write(to:file)
        XCTAssertNotEqual(try reader.fingerprint(at:file).contentHash,first.contentHash)
        XCTAssertEqual(try reader.snapshot(at:file).id.size,7)
    }
}
