import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class FinderAttributeTests:MetadataStageTestCase {
    func testCreatorAndType() throws {try nativeCodes([.creator(Data("APPL".utf8)),.fileType(Data("JPEG".utf8))])}
    func testCreatorOnly() throws {try nativeCodes([.creator(Data("APPL".utf8))])}
    func testTypeOnly() throws {try nativeCodes([.fileType(Data("JPEG".utf8))])}
    func testRemoveCreatorOrType() throws {
        for mutations in [[FinderMutation.creator(Data(repeating:0,count:4))],[.fileType(Data(repeating:0,count:4))],[.creator(Data(repeating:0,count:4)),.fileType(Data(repeating:0,count:4))]] {try nativeCodes(mutations)}
    }
    private func nativeCodes(_ mutations:[FinderMutation]) throws {
        let stage=try ownedStage("paris.jpg"),info=Data((0..<32).map(UInt8.init))
        XCTAssertEqual(info.withUnsafeBytes {setxattr(stage.path,"com.apple.FinderInfo",$0.baseAddress,info.count,0,XATTR_NOFOLLOW)},0)
        let before=try FileIdentityReader().fingerprint(at:stage),result=try FinderAttributeWriter().apply(.init(mutations:mutations),to:stage)
        XCTAssertEqual(result.snapshot.finderInfo,try LegacyFinderInfo(info).applying(mutations))
        XCTAssertEqual(before.contentHash,try FileIdentityReader().fingerprint(at:stage).contentHash)
        let attributes=try FileManager.default.attributesOfItem(atPath:stage.path)
        for mutation in mutations {
            let key:FileAttributeKey,data:Data
            switch mutation {case .creator(let code):key = .hfsCreatorCode;data=code;case .fileType(let code):key = .hfsTypeCode;data=code;default:continue}
            let expected=data.reduce(UInt32(0)) {($0<<8)|UInt32($1)}
            XCTAssertEqual((attributes[key] as? NSNumber)?.uint32Value,expected)
        }
    }
    func testFinderLabel() throws {
        let stage=try ownedStage("paris.jpg"),userTags=try PropertyListSerialization.data(fromPropertyList:["Keep this tag\n1"],format:.binary,options:0)
        XCTAssertEqual(userTags.withUnsafeBytes {setxattr(stage.path,"com.apple.metadata:_kMDItemUserTags",$0.baseAddress,userTags.count,0,XATTR_NOFOLLOW)},0)
        let before=try FileIdentityReader().snapshot(at:stage)
        for label in 0...7 {
            let result=try FinderAttributeWriter().apply(.init(mutations:[.label(label)]),to:stage)
            XCTAssertEqual(Int((result.snapshot.finderInfo ?? Data(repeating:0,count:32))[9]&14)>>1,label)
            XCTAssertEqual(result.snapshot.xattrHashes["com.apple.metadata:_kMDItemUserTags"],before.xattrHashes["com.apple.metadata:_kMDItemUserTags"])
        }
    }
    func testFourByteCodesPreserveOtherFinderInfo() throws {
        let original=Data((0..<32).map(UInt8.init)),creator=Data("APPL".utf8),type=Data("JPEG".utf8)
        let result=try LegacyFinderInfo(original).applying([.creator(creator),.fileType(type)])
        XCTAssertEqual(result.prefix(4),type);XCTAssertEqual(result.subdata(in:4..<8),creator);XCTAssertEqual(result.suffix(24),original.suffix(24))
        XCTAssertThrowsError(try LegacyFinderInfo(original).applying([.creator(Data([1,2,3]))]))
    }
    func testFinderLabelPreservesOtherFlags() throws {
        let original=Data((0..<32).map(UInt8.init))
        for label in 0...7 {
            let result=try LegacyFinderInfo(original).applying([.label(label)])
            XCTAssertEqual(result.prefix(8),original.prefix(8));XCTAssertEqual(result.suffix(22),original.suffix(22))
            XCTAssertEqual(result[8],original[8]);XCTAssertEqual(result[9]&0xf1,original[9]&0xf1);XCTAssertEqual(Int((result[9]&14)>>1),label)
        }
    }
    func testExtensionVisibilityAndUnrelatedAttributes() throws {
        let stage=try ownedStage("paris.jpg"),info=Data((0..<32).map(UInt8.init))
        XCTAssertEqual(info.withUnsafeBytes {setxattr(stage.path,"com.apple.FinderInfo",$0.baseAddress,info.count,0,XATTR_NOFOLLOW)},0)
        let before=try FileIdentityReader().fingerprint(at:stage)
        let changed=try FinderAttributeWriter().apply(.init(mutations:[.extensionHidden(true)]),to:stage)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:stage.path)[.extensionHidden] as? Bool,true)
        XCTAssertEqual(changed.snapshot.creationDate,before.snapshot.creationDate);XCTAssertEqual(changed.snapshot.modificationDate,before.snapshot.modificationDate)
        var expected=info;expected[9] |= 0x10;XCTAssertEqual(changed.snapshot.finderInfo,expected)
        XCTAssertEqual(before.contentHash,try FileIdentityReader().fingerprint(at:stage).contentHash)
        _ = try FinderAttributeWriter().apply(.init(mutations:[.extensionHidden(false)]),to:stage)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:stage.path)[.extensionHidden] as? Bool,false)
    }
    func testWhereFromsOnly() throws {
        let stage=try ownedStage("paris.jpg")
        for (key,value) in [("com.apple.metadata:kMDItemWhereFroms",Data("synthetic origin".utf8)),("com.apple.quarantine",Data("0081;0;RestoreGPSTime;".utf8)),("com.restoregpstime.keep",Data("keep".utf8))] {
            XCTAssertEqual(value.withUnsafeBytes {setxattr(stage.path,key,$0.baseAddress,value.count,0,XATTR_NOFOLLOW)},0)
        }
        let before=try FileIdentityReader().snapshot(at:stage),result=try FinderAttributeWriter().apply(.init(mutations:[.removeWhereFroms]),to:stage)
        var expected=before.xattrHashes;expected["com.apple.metadata:kMDItemWhereFroms"]=nil
        XCTAssertEqual(result.snapshot.xattrHashes,expected)
    }
    func testExplicitUnlockOnly() throws {
        let stage=try ownedStage("paris.jpg"),before=try FileIdentityReader().snapshot(at:stage)
        defer {_ = chflags(stage.path,0)}
        _ = try FinderAttributeWriter().apply(.init(mutations:[.locked(true)]),to:stage)
        XCTAssertTrue(try FileIdentityReader().snapshot(at:stage).isLocked)
        XCTAssertThrowsError(try FinderAttributeWriter().apply(.init(mutations:[.label(3)]),to:stage))
        let result=try FinderAttributeWriter().apply(.init(mutations:[.locked(false),.label(3)]),to:stage)
        XCTAssertFalse(result.snapshot.isLocked);XCTAssertEqual(result.snapshot.permissions,before.permissions);XCTAssertEqual(result.snapshot.aclText,before.aclText)
    }
}
