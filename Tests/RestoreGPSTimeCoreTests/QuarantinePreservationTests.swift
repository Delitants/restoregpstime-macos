import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class QuarantinePreservationTests:MetadataStageTestCase {
    private let quarantine=Data("0081;5f5e1000;RestoreGPSTimeTests;00000000-0000-4000-8000-000000000001".utf8)
    private let binary=Data([0,255,17,0,128])
    private func seed(_ url:URL) throws {
        for (name,data) in [("com.apple.quarantine",quarantine),("com.restoregpstime.binary",binary)] {
            guard data.withUnsafeBytes({setxattr(url.path,name,$0.baseAddress,data.count,0,XATTR_NOFOLLOW)})==0 else {throw SecureFS.error("Seed exact quarantine fixture")}
        }
    }
    private func read(_ name:String,_ url:URL) throws -> Data {
        let size=getxattr(url.path,name,nil,0,0,XATTR_NOFOLLOW)
        guard size>=0 else {throw SecureFS.error("Read preserved attribute")}
        var data=Data(count:size)
        guard data.withUnsafeMutableBytes({getxattr(url.path,name,$0.baseAddress,size,0,XATTR_NOFOLLOW)})==size else {throw SecureFS.error("Read exact preserved attribute")}
        return data
    }
    private func assertPreserved(_ url:URL) throws {
        XCTAssertEqual(try read("com.apple.quarantine",url),quarantine)
        XCTAssertEqual(try read("com.restoregpstime.binary",url),binary)
    }
    func testCopyPreservesOpaqueQuarantineAndUnrelatedAttributes() throws {
        let source=try ownedStage("paris.jpg");try seed(source)
        let before=try FileIdentityReader().fingerprint(at:source)
        let target=source.deletingLastPathComponent().appendingPathComponent("Copied.jpg")
        _=try SecureFS.copy(before,from:source,to:target)
        try assertPreserved(target);try assertPreserved(source)
        XCTAssertEqual(try FileIdentityReader().fingerprint(at:source),before)
    }
    func testArchivePreservesOpaqueQuarantine() throws {
        let stage=try ownedStage("paris.jpg");try seed(stage)
        let archive=try FileAttributeArchive.capture(stage)
        try assertPreserved(archive);try assertPreserved(stage)
    }
    func testAttributeRestorePreservesOpaqueQuarantine() throws {
        let source=try ownedStage("paris.jpg");try seed(source)
        let target=try ownedStage("paris.png")
        try SecureFS.applyMetadata(FileIdentityReader().snapshot(at:source),from:source,to:target)
        try assertPreserved(target);try assertPreserved(source)
    }
}
