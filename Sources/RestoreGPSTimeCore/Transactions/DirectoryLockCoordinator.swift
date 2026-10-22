import Foundation
import Darwin

struct DirectoryLockCoordinator {
    func unlockPrepared(_ record:inout RecoveryRecord,journal:RecoveryJournal,options:RunOptions) throws -> [String:SourceFingerprint] {
        var overrides=[String:SourceFingerprint]()
        for index in record.members.indices {
            let item=record.members[index].item
            guard item.source.snapshot.kind == .directory,item.source.snapshot.isLocked else {continue}
            guard item.mutation.explicitlyUnlocks,record.members[index].backupURL != nil else {throw RestoreError(.conflict,"Directory Unlock requires an explicit preview and a retained original.")}
            guard try FileIdentityReader().fingerprint(at:item.source.snapshot.url)==item.source else {throw RestoreError(.conflict,"A directory changed before its explicit unlock.")}
            record.members[index].step = .unlockPending;try journal.persist(record);try options.checkpoint(.persistedStep(.unlockPending,index:index))
            var coordinationError:NSError?,outcome:Result<Void,Error>?
            NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:item.source.snapshot.url,options:.forMerging,error:&coordinationError) {_ in
                outcome=Result {
                    guard try FileIdentityReader().fingerprint(at:item.source.snapshot.url)==item.source else {throw RestoreError(.conflict,"A directory changed during coordinated unlock.")}
                    try SecureFS.flags(try SecureFS.canonical(item.source.snapshot.url),item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE))
                }
            }
            if let error=coordinationError {throw RestoreError(.io,"Directory unlock coordination failed: "+error.localizedDescription)}
            guard let outcome else {throw RestoreError(.io,"Directory unlock did not grant coordination.")};try outcome.get()
            let current=try FileIdentityReader().fingerprint(at:item.source.snapshot.url)
            record.members[index].after=current;record.members[index].step = .unlocked
            try journal.persist(record);try options.checkpoint(.persistedStep(.unlocked,index:index))
            overrides[item.source.snapshot.id.physicalKey]=current
        }
        return overrides
    }
    func restoreUnfinished(journal:RecoveryJournal,driver:any MutationDriver) async throws -> [(UUID,RecoveryOutcome)] {
        var outcomes=[(UUID,RecoveryOutcome)]()
        let records=try journal.records().filter {$0.phase != .committed && $0.phase != .restored && $0.members.allSatisfy {$0.item.source.snapshot.kind == .directory && $0.backupURL != nil}}
        for record in records.sorted(by:{$0.members[0].item.source.snapshot.url.path.count>$1.members[0].item.source.snapshot.url.path.count}) {
            let outcome=try await RecoveryCoordinator(root:journal.root,driver:driver).restoreGroup(record,journal:journal)
            outcomes.append((record.groupID,outcome))
        }
        return outcomes
    }
}
