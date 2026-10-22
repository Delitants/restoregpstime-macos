import Foundation
import Darwin

public struct FinderAttributeChange:Sendable {
    public let mutations:[FinderMutation]
    public init(mutations:[FinderMutation]) {self.mutations=mutations}
}
public struct FinderAttributeWriter {
    public init() {}
    public func apply(_ change:FinderAttributeChange,to url:URL) throws -> AttributeVerification {
        try StageOwnership.shared.require(url)
        let reader=FileIdentityReader(),before=try reader.snapshot(at:url),mutations=change.mutations
        if before.kind == .directory,mutations.contains(where:{switch $0 {case .creator,.fileType:return true;default:return false}}) {throw RestoreError(.unsupported,"Legacy creator/type codes apply only to ordinary files.")}
        if before.isLocked && !mutations.contains(.locked(false)) {throw RestoreError(.conflict,"Explicitly include Unlock before changing a locked item.")}
        let expectedInfo=try LegacyFinderInfo(before.finderInfo).applying(mutations)
        let legacy=mutations.filter {if case .extensionHidden=$0 {return false};return true},legacyInfo=try LegacyFinderInfo(before.finderInfo).applying(legacy)
        let parent=try SecureFS.directory(url.deletingLastPathComponent());defer {close(parent)}
        let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open owned Finder stage")};defer {close(fd)}
        var status=stat();guard fstat(fd,&status)==0,UInt64(status.st_ino)==before.id.inode else {throw RestoreError(.conflict,"The Finder stage changed while opening it.")}
        if before.isLocked {guard fchflags(fd,before.flags & ~UInt32(UF_IMMUTABLE))==0 else {throw SecureFS.error("Explicitly unlock stage")}}
        if legacyInfo != LegacyFinderInfo(before.finderInfo).data {
            guard legacyInfo.withUnsafeBytes({fsetxattr(fd,"com.apple.FinderInfo",$0.baseAddress,32,0,0)})==0 else {throw SecureFS.error("Set selected FinderInfo fields")}
        }
        for mutation in mutations {
            switch mutation {
            case .extensionHidden(let value):
                try FileManager.default.setAttributes([.extensionHidden:value],ofItemAtPath:url.path)
                try StageOwnership.shared.require(url)
            case .removeWhereFroms:
                if fremovexattr(fd,"com.apple.metadata:kMDItemWhereFroms",0) != 0 && errno != ENOATTR {throw SecureFS.error("Remove WhereFroms")}
            default:break
            }
        }
        var flags=before.flags
        for mutation in mutations {if case .locked(let value)=mutation {flags=value ? flags|UInt32(UF_IMMUTABLE):flags & ~UInt32(UF_IMMUTABLE)}}
        guard fchflags(fd,flags)==0,fsync(fd)==0 else {throw SecureFS.error("Set and sync selected Finder flags")}
        let after=try reader.snapshot(at:url)
        var expectedXattrs=before.xattrHashes
        if expectedInfo != LegacyFinderInfo(before.finderInfo).data || mutations.contains(where:{if case .extensionHidden=$0 {return true};return false}) {expectedXattrs["com.apple.FinderInfo"]=after.xattrHashes["com.apple.FinderInfo"]}
        if mutations.contains(.removeWhereFroms) {expectedXattrs["com.apple.metadata:kMDItemWhereFroms"]=nil}
        guard LegacyFinderInfo(after.finderInfo).data==expectedInfo,after.xattrHashes==expectedXattrs,after.flags==flags,after.creationDate==before.creationDate,after.modificationDate==before.modificationDate,after.permissions==before.permissions,after.ownerID==before.ownerID,after.groupID==before.groupID,after.aclText==before.aclText else {throw RestoreError(.verificationFailed,"Unselected FinderInfo or filesystem attributes changed.")}
        return .init(snapshot:after,notes:[])
    }
}
