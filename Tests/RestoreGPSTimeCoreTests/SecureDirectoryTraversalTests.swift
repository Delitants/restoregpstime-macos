import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class SecureDirectoryTraversalTests:CoreTestCase {
    func testSearchableAncestorNeedsNoReadAccessForChildTransactions() throws {
        let root=try FileSystemPath.canonicalDirectory(workspace)
        let ancestor=root.appendingPathComponent("searchable-only"),child=ancestor.appendingPathComponent("authorized-child")
        try FileManager.default.createDirectory(at:child,withIntermediateDirectories:true)
        XCTAssertEqual(chmod(ancestor.path,0o300),0)
        defer {_=chmod(ancestor.path,0o700)}
        let target=child.appendingPathComponent("transaction")
        let directory=try SecureFS.directory(target,create:true,mode:0o700);defer {close(directory)}
        let file=openat(directory,"record",O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0o600)
        XCTAssertGreaterThanOrEqual(file,0);if file>=0 {close(file)}
        XCTAssertEqual(fsync(directory),0)
        var actual=stat();XCTAssertEqual(fstat(directory,&actual),0)
        XCTAssertEqual(actual.st_mode & S_IFMT,S_IFDIR)
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.appendingPathComponent("record").path))
    }
    func testTraversalRejectsAncestorAndLeafSymlinks() throws {
        let root=try FileSystemPath.canonicalDirectory(workspace),target=root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at:target.appendingPathComponent("child"),withIntermediateDirectories:true)
        let link=root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        for path in [link,link.appendingPathComponent("child")] {
            for create in [false,true] {XCTAssertThrowsError(try SecureFS.directory(path,create:create))}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.appendingPathComponent("unexpected").path))
    }
}
