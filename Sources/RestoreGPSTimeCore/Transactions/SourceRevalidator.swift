import Foundation

struct SourceRevalidator {
    func validate(_ group:PlannedGroup,overrides:[String:SourceFingerprint]=[:]) throws {
        var seen=Set<String>()
        for item in group.items where seen.insert(item.source.snapshot.id.physicalKey).inserted {
            let expected=overrides[item.source.snapshot.id.physicalKey] ?? item.source
            guard try FileIdentityReader().fingerprint(at:expected.snapshot.url)==expected else {throw RestoreError(.conflict,"The source changed before the protected commit.")}
        }
    }
}

extension SourceRevalidator {
    func refreshedDirectoryOverrides(plan:BatchPlan,journal:RecoveryJournal,previous:[String:SourceFingerprint]) throws -> [String:SourceFingerprint] {
        let records=try journal.records()
        let ownPaths=records.flatMap {record in record.stageDirectories+record.members.filter {$0.step != .pending}.flatMap {[$0.item.source.snapshot.url,$0.item.name.finalURL]}}
        var result=previous
        for item in plan.groups.flatMap(\.items) where item.source.snapshot.kind == .directory {
            let expected=previous[item.source.snapshot.id.physicalKey] ?? item.source
            if ownPaths.contains(where:{$0.path != item.source.snapshot.url.path && BatchPlanner.isWithin($0,item.source.snapshot.url)}) {
                let current=try FileIdentityReader().fingerprint(at:item.source.snapshot.url)
                guard current.snapshot.id.physicalKey==expected.snapshot.id.physicalKey,SecureFS.stableDirectoryAttributes(current.snapshot,expected.snapshot),current.snapshot.creationDate==expected.snapshot.creationDate else {throw RestoreError(.conflict,"A folder's unrelated attributes changed during the batch.")}
                result[item.source.snapshot.id.physicalKey]=current
            }
        }
        return result
    }
}
