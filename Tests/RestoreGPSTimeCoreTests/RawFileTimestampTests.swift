import XCTest
import Darwin
@testable import RestoreGPSTimeCore

private struct RawTimes:Equatable {let birthSeconds:Int,birthNanos:Int,modifiedSeconds:Int,modifiedNanos:Int}
final class RawFileTimestampTests:MetadataStageTestCase {
    private func raw(_ url:URL) throws -> RawTimes {
        var value=stat();guard lstat(url.path,&value)==0 else {throw SecureFS.error("Inspect exact fixture times")}
        return .init(birthSeconds:value.st_birthtimespec.tv_sec,birthNanos:value.st_birthtimespec.tv_nsec,modifiedSeconds:value.st_mtimespec.tv_sec,modifiedNanos:value.st_mtimespec.tv_nsec)
    }
    private func seed(_ url:URL) throws -> RawTimes {
        var list=attrlist();list.bitmapcount=UInt16(ATTR_BIT_MAP_COUNT);list.commonattr=attrgroup_t(ATTR_CMN_CRTIME|ATTR_CMN_MODTIME)
        var values=[timespec(tv_sec:1_577_836_800,tv_nsec:123_456_789),timespec(tv_sec:1_609_459_200,tv_nsec:987_654_321)]
        let fd=open(url.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw SecureFS.error("Open timestamp fixture")};defer {close(fd)}
        guard values.withUnsafeMutableBytes({fsetattrlist(fd,&list,$0.baseAddress,$0.count,0)})==0 else {throw SecureFS.error("Seed exact fixture dates")}
        let expected=RawTimes(birthSeconds:1_577_836_800,birthNanos:123_456_789,modifiedSeconds:1_609_459_200,modifiedNanos:987_654_321)
        XCTAssertEqual(try raw(url),expected,"The test volume must represent the seeded nanoseconds before the production operation.")
        return expected
    }
    func testIndependentCopyPreservesExactBirthAndModificationTimes() throws {
        let source=try ownedStage("paris.jpg"),expected=try seed(source),fingerprint=try FileIdentityReader().fingerprint(at:source)
        let destination=try SecureFS.canonical(source.deletingLastPathComponent().appendingPathComponent("Copied.jpg"))
        _=try SecureFS.copy(fingerprint,from:try SecureFS.canonical(source),to:destination)
        XCTAssertEqual(try raw(destination),expected);XCTAssertEqual(try raw(source),expected)
    }
    func testAttributeRestorePreservesExactBirthAndModificationTimes() throws {
        let source=try ownedStage("paris.jpg"),expected=try seed(source),snapshot=try FileIdentityReader().snapshot(at:source),destination=try ownedStage("paris.png")
        try SecureFS.applyMetadata(snapshot,from:try SecureFS.canonical(source),to:try SecureFS.canonical(destination))
        XCTAssertEqual(try raw(destination),expected)
    }
    func testDateWriterPreservesUnselectedNanoseconds() throws {
        for selectedCreation in [false,true] {
            let stage=try ownedStage(selectedCreation ? "paris.jpg":"paris.png"),expected=try seed(stage)
            let date=try utc(selectedCreation ? "2019-01-01T00:00:00Z":"2022-01-01T00:00:00Z")
            _=try FileDateWriter().apply(.init(creationDate:selectedCreation ? date:nil,modificationDate:selectedCreation ? nil:date),to:stage)
            let actual=try raw(stage)
            if selectedCreation {XCTAssertEqual(actual.modifiedSeconds,expected.modifiedSeconds);XCTAssertEqual(actual.modifiedNanos,expected.modifiedNanos)}
            else {XCTAssertEqual(actual.birthSeconds,expected.birthSeconds);XCTAssertEqual(actual.birthNanos,expected.birthNanos)}
        }
    }
}
