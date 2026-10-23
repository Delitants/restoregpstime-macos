import Foundation
import Darwin

// A persisted intent is not proof that the version retired by rename/exchange
// was the previewed source. Inspect that actual version, including after a crash.
enum HeldOriginalVerifier {
    static func require(_ url:URL,member:RecoveryMember) throws {
        let held:SourceFingerprint
        do {held=try FileIdentityReader().fingerprint(at:url)}
        catch {throw conflict(url,"The held original cannot be verified")}
        guard SecureFS.matches(held,member.item.source,ignoreChangeTime:true,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw conflict(url,"A newer or unrecognized original is retained")}
    }
    static func validateRecovery(_ member:RecoveryMember,record:RecoveryRecord) throws {
        guard record.options.mode == .modifyInPlace,member.item.mutation.outputKind == .sourceCopy,member.item.source.snapshot.kind == .regular else {return}
        if let held=member.heldOriginalURL,SecureFS.exists(held) {try require(held,member:member)}
        let source=try SecureFS.canonical(member.item.source.snapshot.url),target=try Committer.target(member.item)
        guard source.path==target.path,let staged=member.staged,SecureFS.exists(target) else {return}
        let current=try FileIdentityReader().fingerprint(at:target)
        if current.snapshot.id.physicalKey==staged.snapshot.id.physicalKey {
            // The staged inode is at the source name, so an exchange occurred even
            // if the process stopped before persisting its completion/diagnostics.
            if record.compactCleanup != nil,record.options.effectiveBackupMode != .full,let path=member.stageURL,!SecureFS.exists(path) {return}
            guard let held=member.stageURL else {throw conflict(source,"The exchanged original path is missing")}
            try require(held,member:member)
        }
    }
    private static func conflict(_ path:URL,_ reason:String)->RestoreError {
        .init(.recoveryNeeded,reason+" at "+path.path+". Original-location recovery is blocked for this group. Retain this version and the recovery vault; separate-folder recovery remains available.")
    }
}
