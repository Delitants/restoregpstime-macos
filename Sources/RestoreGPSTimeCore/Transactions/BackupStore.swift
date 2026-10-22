import Foundation

struct BackupStore {
    func prepare(_ record:inout RecoveryRecord,journal:RecoveryJournal,options:RunOptions) throws {
        guard record.options.mode == .modifyInPlace else {return}
        let root=journal.batchDirectory.appendingPathComponent("originals/\(record.groupID.uuidString)")
        try SecureFS.privateDirectory(root)
        let total=record.members.filter {$0.item.mutation.outputKind == .sourceCopy}.reduce(UInt64(1_048_576)) {$0 &+ $1.item.source.snapshot.id.size}
        try SecureFS.requireSpace(at:root,bytes:total)
        for index in record.members.indices where record.members[index].item.mutation.outputKind == .sourceCopy {
            let item=record.members[index].item
            try options.checkpoint(.beforeBackup(item.name.sourceKey))
            let target=root.appendingPathComponent("\(index).original")
            let current=try FileIdentityReader().fingerprint(at:item.source.snapshot.url)
            let backup=try SecureFS.copy(current,from:try SecureFS.canonical(item.source.snapshot.url),to:target,vault:true)
            guard backup.contentHash==item.source.contentHash else {throw RestoreError(.verificationFailed,"The retained original does not match preview.")}
            record.members[index].backupURL=target;record.members[index].backupHash=backup.contentHash
        }
    }
}
