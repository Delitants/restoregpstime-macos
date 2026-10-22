import Foundation
import Darwin

public struct FileDateChange:Sendable {
    public let creationDate:Date?,modificationDate:Date?
    public init(creationDate:Date?=nil,modificationDate:Date?=nil) {self.creationDate=creationDate;self.modificationDate=modificationDate}
}
public struct AttributeVerification:Sendable {
    public let snapshot:FileSnapshot,notes:[String]
}
public struct FileDateWriter {
    public init() {}
    public func apply(_ change:FileDateChange,to url:URL) throws -> AttributeVerification {
        try StageOwnership.shared.require(url)
        let reader=FileIdentityReader(),before=try reader.snapshot(at:url)
        guard !before.isLocked else {throw RestoreError(.conflict,"Explicitly unlock the stage before changing its dates.")}
        var list=attrlist();list.bitmapcount=UInt16(ATTR_BIT_MAP_COUNT)
        var values=[timespec]()
        func value(_ date:Date) throws -> timespec {
            let seconds=floor(date.timeIntervalSince1970)
            guard seconds.isFinite,seconds>=Double(Int64.min),seconds<Double(Int64.max) else {throw RestoreError(.unsupported,"The selected date exceeds the filesystem timestamp range.")}
            return timespec(tv_sec:Int(seconds),tv_nsec:Int((date.timeIntervalSince1970-seconds)*1e9))
        }
        if change.creationDate != nil || change.modificationDate != nil {
            // macOS may clamp birth time when an earlier mtime is submitted alone.
            // Explicitly submit the preserved companion value in the same atomic attribute call.
            list.commonattr=attrgroup_t(ATTR_CMN_CRTIME|ATTR_CMN_MODTIME)
            values=[try value(change.creationDate ?? before.creationDate),try value(change.modificationDate ?? before.modificationDate)]
        }
        if !values.isEmpty {
            let parent=try SecureFS.directory(url.deletingLastPathComponent());defer {close(parent)}
            let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open owned date stage")};defer {close(fd)}
            var status=stat();guard fstat(fd,&status)==0,UInt64(status.st_ino)==before.id.inode else {throw RestoreError(.conflict,"The date stage changed while opening it.")}
            guard values.withUnsafeMutableBytes({fsetattrlist(fd,&list,$0.baseAddress,$0.count,0)})==0,fsync(fd)==0 else {throw SecureFS.error("Set and sync selected filesystem dates")}
        }
        let after=try reader.snapshot(at:url)
        let creation=change.creationDate ?? before.creationDate,modification=change.modificationDate ?? before.modificationDate
        guard abs(after.creationDate.timeIntervalSince(creation))<=0.000001,abs(after.modificationDate.timeIntervalSince(modification))<=0.000001 else {throw RestoreError(.unsupported,"The target volume cannot represent the selected dates at the required precision.")}
        guard after.flags==before.flags,after.permissions==before.permissions,after.ownerID==before.ownerID,after.groupID==before.groupID,after.xattrHashes==before.xattrHashes,after.aclText==before.aclText else {throw RestoreError(.verificationFailed,"A date write changed an unselected filesystem attribute.")}
        return .init(snapshot:after,notes:[])
    }
}
