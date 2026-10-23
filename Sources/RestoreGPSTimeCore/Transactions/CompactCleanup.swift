import Foundation
import Darwin

/// Cleanup intent is persisted after every member is committed. Missing owned
/// paths are then expected after a crash; present paths still require proof.
enum CompactCleanup {
    static func committed(_ record:inout RecoveryRecord,journal:RecoveryJournal) throws {
        guard record.options.effectiveBackupMode != .full else {return}
        if record.compactCleanup==nil {record.compactCleanup=false;try journal.persist(record)}
        for member in record.members where member.item.source.snapshot.kind == .regular {
            if record.options.mode == .modifyInPlace,member.item.mutation.outputKind == .sourceCopy {
                if record.options.effectiveBackupMode == .metadata {_ = try CompactBackupStore(journal:journal).payload(member,record:record)}
                guard let after=member.after,SecureFS.matches(try FileIdentityReader().fingerprint(at:after.snapshot.url),after) else {throw RestoreError(.conflict,"Output changed before compact cleanup; held originals retained.")}
                for path in [member.stageURL,member.heldOriginalURL].compactMap({$0}) where SecureFS.exists(path) {
                    try HeldOriginalVerifier.require(path,member:member)
                    try remove(path,expected:try FileIdentityReader().fingerprint(at:path))
                }
            }
        }
        record.compactCleanup=true;try journal.persist(record)
    }
    static func restored(_ record:RecoveryRecord) throws {
        guard record.options.effectiveBackupMode != .full else {return}
        for member in record.members {
            if let retired=member.recoveryRetiredURL,let expected=member.recoveryRetiredFingerprint,SecureFS.exists(retired) {
                let actual=try FileIdentityReader().fingerprint(at:retired)
                guard SecureFS.matches(actual,expected,ignoreChangeTime:true,flags:expected.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.conflict,"Displaced output changed; cleanup stopped.")}
                try remove(retired,expected:actual)
            }
            if let backup=member.backupURL,member.compactHash != nil,backup.lastPathComponent.hasPrefix("compact-"),SecureFS.exists(backup) {
                let actual=try FileIdentityReader().fingerprint(at:backup)
                guard actual.contentHash==member.item.source.contentHash,SecureFS.attributesEqual(actual.snapshot,member.item.source.snapshot,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.conflict,"Materialized compact original changed; cleanup stopped.")}
                try remove(backup,expected:actual)
            }
            for path in [member.stageURL,member.heldOriginalURL].compactMap({$0}) where SecureFS.exists(path) && member.item.source.snapshot.kind == .regular {
                // A stage exchanged by undo is the recorded retired output above.
                let actual=try FileIdentityReader().fingerprint(at:path)
                if (try? HeldOriginalVerifier.require(path,member:member)) != nil {
                    try remove(path,expected:actual);continue
                }
                if path==member.stageURL,record.compactCleanup==nil {
                    // A crash before publication leaves a copied stage, not the
                    // original inode. Remove it only with durable stage identity.
                    guard let staged=member.staged else {continue}
                    guard SecureFS.matches(actual,staged,ignoreChangeTime:true) else {throw RestoreError(.conflict,"An unpublished stage changed; evidence retained.")}
                } else {try HeldOriginalVerifier.require(path,member:member)}
                try remove(path,expected:actual)
            }
        }
    }
    static func remove(_ url:URL,expected:SourceFingerprint) throws {
        let parent=try SecureFS.directory(url.deletingLastPathComponent());defer {close(parent)}
        guard SecureFS.matches(try FileIdentityReader().fingerprint(at:url),expected) else {throw RestoreError(.conflict,"Owned cleanup evidence changed.")}
        if expected.snapshot.isLocked {throw RestoreError(.conflict,"Cleanup will not unlock unexpected retained media.")}
        guard unlinkat(parent,url.lastPathComponent,expected.snapshot.kind == .directory ? AT_REMOVEDIR:0)==0,fsync(parent)==0 else {throw SecureFS.error("Remove verified temporary media")}
    }
}
