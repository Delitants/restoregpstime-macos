import Foundation
import Darwin

public struct FileDateChange:Sendable {
    public let creationDate:Date?,modificationDate:Date?
    public let creationTimestamp:FileTimestamp?,modificationTimestamp:FileTimestamp?
    public init(creationDate:Date?=nil,modificationDate:Date?=nil,creationTimestamp:FileTimestamp?=nil,modificationTimestamp:FileTimestamp?=nil) {self.creationDate=creationDate;self.modificationDate=modificationDate;self.creationTimestamp=creationTimestamp;self.modificationTimestamp=modificationTimestamp}
}
public struct AttributeVerification:Sendable {public let snapshot:FileSnapshot,notes:[String]}
public struct FileDateWriter {
    public init() {}
    public func apply(_ change:FileDateChange,to url:URL) throws -> AttributeVerification {
        try StageOwnership.shared.require(url)
        let reader=FileIdentityReader(),before=try reader.snapshot(at:url)
        guard !before.isLocked else {throw RestoreError(.conflict,"Explicitly unlock the stage before changing its dates.")}
        func intended(_ exact:FileTimestamp?,_ date:Date?,_ oldExact:FileTimestamp?,_ oldDate:Date) throws -> FileTimestamp {
            if let exact {return exact};if let date {return try FileTimestamp(date:date)}
            return try oldExact ?? FileTimestamp(date:oldDate)
        }
        let creation=try intended(change.creationTimestamp,change.creationDate,before.creationTimestamp,before.creationDate)
        let modification=try intended(change.modificationTimestamp,change.modificationDate,before.modificationTimestamp,before.modificationDate)
        if change.creationDate != nil || change.modificationDate != nil || change.creationTimestamp != nil || change.modificationTimestamp != nil {
            var list=attrlist();list.bitmapcount=UInt16(ATTR_BIT_MAP_COUNT);list.commonattr=attrgroup_t(ATTR_CMN_CRTIME|ATTR_CMN_MODTIME)
            // Submit both intended values together; the unselected companion uses
            // raw stat precision, and an earlier mtime cannot clamp birth time.
            var values=[creation.timeSpec,modification.timeSpec]
            let parent=try SecureFS.directory(url.deletingLastPathComponent());defer {close(parent)}
            let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open owned date stage")};defer {close(fd)}
            var status=stat();guard fstat(fd,&status)==0,UInt64(status.st_ino)==before.id.inode else {throw RestoreError(.conflict,"The date stage changed while opening it.")}
            guard values.withUnsafeMutableBytes({fsetattrlist(fd,&list,$0.baseAddress,$0.count,0)})==0,fsync(fd)==0 else {throw SecureFS.error("Set and sync selected filesystem dates")}
        }
        let after=try reader.snapshot(at:url)
        guard after.creationTimestamp==creation,after.modificationTimestamp==modification else {throw RestoreError(.unsupported,"The target volume cannot represent the intended dates at the required precision.")}
        guard after.flags==before.flags,after.permissions==before.permissions,after.ownerID==before.ownerID,after.groupID==before.groupID,after.xattrHashes==before.xattrHashes,after.aclText==before.aclText else {throw RestoreError(.verificationFailed,"A date write changed an unselected filesystem attribute.")}
        return .init(snapshot:after,notes:[])
    }
}
