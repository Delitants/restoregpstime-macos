import Foundation
import Darwin

public struct RecoveryCoordinator:Sendable {
    let root:URL
    let driver:any MutationDriver
    let options:RunOptions
    public init(root:URL,driver:any MutationDriver,options:RunOptions=RunOptions()) {self.root=root;self.driver=driver;self.options=options}
    /// nil selects every group; a selected source key always includes all linked
    /// siblings in its protected group. An empty set performs no restoration.
    public func restore(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?=nil) async throws -> RecoveryOutcome {
        let worker=Task.detached(priority:.userInitiated) {try await restoreBlocking(batchID:batchID,choice:choice,selectedSourceKeys:selectedSourceKeys)}
        return try await worker.value
    }
    private func restoreBlocking(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?) async throws -> RecoveryOutcome {
        let journal=try RecoveryJournal(root:root,batchID:batchID)
        var restored=[URL](),conflicts=[String]()
        var ownRestoredPaths=[URL]()
        var records=try journal.records().filter {record in selectedSourceKeys.map {selected in record.members.contains {selected.contains($0.item.name.sourceKey)}} ?? true}.sorted {a,b in
            let ad=a.members.allSatisfy {$0.item.source.snapshot.kind == .directory},bd=b.members.allSatisfy {$0.item.source.snapshot.kind == .directory}
            if ad != bd {return !ad}
            if ad {return a.members[0].item.source.snapshot.url.path.count>b.members[0].item.source.snapshot.url.path.count}
            return a.groupID.uuidString<b.groupID.uuidString
        }
        // Refuse completed No backup groups before directory-unlock preflight.
        // Their children must never cause an otherwise disabled undo to mutate flags.
        records.removeAll {record in
            let unavailable=record.options.effectiveBackupMode == .none && (record.phase == .committed || record.compactCleanup != nil)
            if unavailable {conflicts.append("No backup was selected; completed changes have no retained undo.")}
            return unavailable
        }
        var blockedDirectories=[URL]()
        if case .originalLocations=choice {
            // A selected locked parent must permit child restores before its own final
            // metadata/lock restoration. Validate it against the journal before unlocking.
            for recordIndex in records.indices {
                for memberIndex in records[recordIndex].members.indices {
                    let member=records[recordIndex].members[memberIndex]
                    guard member.item.source.snapshot.kind == .directory else {continue}
                    let target=try Committer.target(member.item)
                    let pendingDescendant=records.contains {record in record.members.contains {child in
                        !child.restored && (child.after != nil || child.step != .pending) && child.item.source.snapshot.kind != .directory && child.item.name.finalURL.path != target.path && BatchPlanner.isWithin(child.item.name.finalURL,target)
                    }}
                    guard pendingDescendant,SecureFS.exists(target),try FileIdentityReader().snapshot(at:target).isLocked else {continue}
                    do {
                        _ = try state(member,record:records[recordIndex])
                        records[recordIndex].phase = .restoring;try journal.persist(records[recordIndex])
                        try coordinated(target) {
                            _ = try state(records[recordIndex].members[memberIndex],record:records[recordIndex])
                            let current=try FileIdentityReader().snapshot(at:target)
                            try SecureFS.flags(target,current.flags & ~UInt32(UF_IMMUTABLE))
                        }
                    } catch {blockedDirectories.append(target);conflicts.append("Locked folder recovery stopped: "+error.localizedDescription)}
                }
            }
        }
        for var record in records {
            if record.members.contains(where:{member in blockedDirectories.contains {BatchPlanner.isWithin(member.item.name.finalURL,$0)}}) {continue}
            for index in record.members.indices where record.members[index].item.source.snapshot.kind == .directory {
                let member=record.members[index],source=member.item.source.snapshot
                let target=try Committer.target(member.item)
                if SecureFS.exists(target),ownRestoredPaths.contains(where:{$0.path != target.path && BatchPlanner.isWithin($0,target)}) {
                    let current=try FileIdentityReader().fingerprint(at:target)
                    let expected=member.after?.snapshot ?? source
                    let flags=record.phase == .restoring ? expected.flags & ~UInt32(UF_IMMUTABLE):expected.flags
                    if current.snapshot.id.physicalKey==expected.id.physicalKey,SecureFS.stableDirectoryAttributes(current.snapshot,expected,flags:flags),FileTimestamp.matches(current.snapshot.creationTimestamp,expected.creationTimestamp,date:current.snapshot.creationDate,expectedDate:expected.creationDate) {
                        record.members[index].after=current;try journal.persist(record)
                    }
                }
            }
            let outcome:RecoveryOutcome
            switch choice {
            case .originalLocations:outcome=try await restoreGroup(record,journal:journal)
            case .separateFolder(let output):outcome=try await restoreSeparately(record,journal:journal,output:output)
            }
            restored+=outcome.restored;conflicts+=outcome.conflicts;ownRestoredPaths+=outcome.restored
            if outcome.isComplete {ownRestoredPaths+=record.members.filter {$0.item.mutation.outputKind == .xmpSidecar || record.options.mode == .saveCopies}.map {$0.item.name.finalURL}}
        }
        return .init(batchID:batchID,restored:restored,conflicts:conflicts)
    }
    private enum State {case untouched,duplicate,changed,restored,notPublished}
    private func finalFlags(_ member:RecoveryMember)->UInt32 {
        let lock=member.item.mutation.finder.compactMap {if case .locked(let value)=$0 {return value};return nil}.last ?? member.item.source.snapshot.isLocked
        let base=member.staged?.snapshot.flags ?? 0
        return lock ? base|UInt32(UF_IMMUTABLE):base & ~UInt32(UF_IMMUTABLE)
    }
    private func state(_ member:RecoveryMember,record:RecoveryRecord) throws -> State {
        let reader=FileIdentityReader(),source=try SecureFS.canonical(member.item.source.snapshot.url),target=try Committer.target(member.item)
        // Persisted retirement proof must be checked before an already-restored
        // source can mask an external edit to the displaced output.
        if let held=member.recoveryRetiredURL,let expected=member.recoveryRetiredFingerprint,SecureFS.exists(held) {
            let actual=try reader.fingerprint(at:held)
            let preparedSwap=try member.restoreStageURL==held && member.restoreFingerprint.map {SecureFS.matches(actual,$0)}==true && SecureFS.exists(target) && SecureFS.matches(try reader.fingerprint(at:target),expected)
            guard preparedSwap || SecureFS.matches(actual,expected,ignoreChangeTime:true,flags:expected.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {
                throw RestoreError(.conflict,"A displaced output changed; both versions are retained. Inspect "+held.path)
            }
        }
        if let restored=member.restoreFingerprint,SecureFS.exists(source) {
            let current=try reader.fingerprint(at:source)
            if SecureFS.matches(current,restored,ignoreChangeTime:true,flags:member.item.source.snapshot.flags) || SecureFS.matches(current,restored,ignoreChangeTime:true) {return .restored}
        }
        try HeldOriginalVerifier.validateRecovery(member,record:record)
        if record.options.mode == .modifyInPlace && member.item.mutation.outputKind == .sourceCopy && SecureFS.exists(source) {
            let current=try reader.fingerprint(at:source)
            let originalMatches=SecureFS.matches(current,member.item.source) || (member.item.mutation.explicitlyUnlocks && member.item.source.snapshot.isLocked && member.step != .pending && SecureFS.matches(current,member.item.source,ignoreChangeTime:true,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)))
            if originalMatches {
                if source.path != target.path,let expected=member.staged,SecureFS.exists(target),SecureFS.matches(try reader.fingerprint(at:target),expected,ignoreChangeTime:true,flags:finalFlags(member)) {return .duplicate}
                return .untouched
            }
            if source.path != target.path {
                let caseAlias=member.item.name.needsTemporaryRename && member.staged.map {current.snapshot.id.physicalKey==$0.snapshot.id.physicalKey}==true
                guard caseAlias else {throw RestoreError(.conflict,"Recovery found a newer or unrecognized source at "+source.path+". No member of this group will be restored over it.")}
            }
        }
        if SecureFS.exists(target) {
            let current=try reader.fingerprint(at:target)
            if let after=member.after,SecureFS.matches(current,after) {return .changed}
            if member.item.source.snapshot.kind == .directory,let expected=member.staged,current.snapshot.id.physicalKey==member.item.source.snapshot.id.physicalKey,SecureFS.attributesEqual(current.snapshot,expected.snapshot) {return .changed}
            if let expected=member.staged,member.after==nil,SecureFS.matches(current,expected,ignoreChangeTime:true,flags:finalFlags(member)) || SecureFS.matches(current,expected,ignoreChangeTime:true) {return .changed}
            if record.phase == .restoring,let after=member.after,SecureFS.matches(current,after,ignoreChangeTime:true,flags:after.snapshot.flags & ~UInt32(UF_IMMUTABLE)) {return .changed}
            throw RestoreError(.conflict,"Recovery will not replace a newer or unrecognized file: \(target.lastPathComponent)")
        }
        if record.options.mode == .saveCopies || member.item.mutation.outputKind == .xmpSidecar {return .notPublished}
        if let held=member.heldOriginalURL,SecureFS.exists(held) {return .notPublished}
        if let restore=member.restoreStageURL,SecureFS.exists(restore),record.phase == .restoring {return .notPublished}
        if record.options.effectiveBackupMode == .metadata,record.compactCleanup != nil {
            throw RestoreError(.conflict,"Compact undo requires the unchanged output media. The media payload is missing; the compact database cannot recreate deleted or damaged media.")
        }
        throw RestoreError(.conflict,"An expected original/output is missing; originals remain retained for separate-folder recovery.")
    }
    private func prepareBackup(index:Int,record:inout RecoveryRecord,journal:RecoveryJournal) throws {
        let member=record.members[index]
        if let existing=member.backupURL,SecureFS.exists(existing) {return}
        if record.options.effectiveBackupMode == .full {return}
        // Prefer the verified original inode while an interrupted commit still
        // retains it. This also protects recovery if compact capture was damaged.
        if record.compactCleanup != true,let held=[member.heldOriginalURL,member.stageURL].compactMap({$0}).first(where:{SecureFS.exists($0) && (try? HeldOriginalVerifier.require($0,member:member)) != nil}) {
            record.members[index].backupURL=held;record.members[index].backupHash=member.item.source.contentHash
            try journal.persist(record);return
        }
        if member.compactHash != nil {
            let payload=try CompactBackupStore(journal:journal).payload(member,record:record)
            guard let root=member.stageURL?.deletingLastPathComponent() else {throw RestoreError(.recoveryNeeded,"Compact staging directory is unavailable.")}
            if !SecureFS.exists(root) {try SecureFS.privateDirectory(root)}
            let path=root.appendingPathComponent("compact-\(CompactBackupStore.hash(Data(member.item.name.sourceKey.utf8))).original")
            if !SecureFS.exists(path) {
                let target=try Committer.target(member.item),before=try FileIdentityReader().fingerprint(at:target)
                guard before.contentHash==payload.outputHash else {throw RestoreError(.conflict,"Compact undo requires the unchanged output media.")}
                if member.item.source.snapshot.kind == .directory {
                    let parent=try SecureFS.directory(root);defer {close(parent)}
                    guard mkdirat(parent,path.lastPathComponent,0o700)==0 else {throw SecureFS.error("Create compact directory attributes stage")}
                } else {
                    guard let delta=payload.delta else {throw RestoreError(.invalidInput,"Compact byte recipe is missing.")}
                    try delta.restore(output:target,to:path)
                }
                try payload.applyAttributes(to:path)
                guard try FileIdentityReader().fingerprint(at:target)==before else {throw RestoreError(.conflict,"Output changed during compact reconstruction; originals retained.")}
            }
            let materialized=try FileIdentityReader().fingerprint(at:path)
            guard materialized.contentHash==member.item.source.contentHash,SecureFS.attributesEqual(materialized.snapshot,member.item.source.snapshot,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.verificationFailed,"Compact reconstruction failed exact original verification.")}
            record.members[index].backupURL=path;record.members[index].backupHash=materialized.contentHash
            try journal.persist(record)
        } else {
            // Incomplete transactions retain their original inode until the whole
            // group commits. No-backup must still recover interrupted publication.
            guard let held=[member.heldOriginalURL,member.stageURL].compactMap({$0}).first(where:{SecureFS.exists($0) && (try? HeldOriginalVerifier.require($0,member:member)) != nil}) else {throw RestoreError(.recoveryNeeded,"The incomplete transaction's held original is unavailable.")}
            record.members[index].backupURL=held;record.members[index].backupHash=member.item.source.contentHash
            try journal.persist(record)
        }
    }
    private func verifiedBackup(_ member:RecoveryMember,journal:RecoveryJournal) throws -> SourceFingerprint {
        guard let url=member.backupURL,(BatchPlanner.isWithin(url,journal.batchDirectory.appendingPathComponent("originals")) || (member.compactHash != nil && url==member.stageURL?.deletingLastPathComponent().appendingPathComponent("compact-\(CompactBackupStore.hash(Data(member.item.name.sourceKey.utf8))).original")) || url==member.heldOriginalURL || url==member.stageURL) else {throw RestoreError(.recoveryNeeded,"A verified retained original is unavailable.")}
        let fingerprint=try FileIdentityReader().fingerprint(at:url)
        guard fingerprint.snapshot.kind==member.item.source.snapshot.kind,fingerprint.contentHash==member.backupHash,fingerprint.contentHash==member.item.source.contentHash,fingerprint.snapshot.xattrHashes==member.item.source.snapshot.xattrHashes else {throw RestoreError(.verificationFailed,"The retained original changed; recovery stopped.")}
        return fingerprint
    }
    func restoreGroup(_ original:RecoveryRecord,journal:RecoveryJournal) async throws -> RecoveryOutcome {
        var record=original,conflicts=[String](),restored=[URL]()
        do {
            if record.options.effectiveBackupMode == .none,(record.phase == .committed || record.compactCleanup != nil) {throw RestoreError(.unsupported,"No backup was selected; completed changes have no retained undo.")}
            for index in record.members.indices {
                let member=record.members[index],current=try state(member,record:record)
                if record.options.mode == .modifyInPlace && member.item.mutation.outputKind == .sourceCopy && (current == .changed || current == .notPublished) {
                    try prepareBackup(index:index,record:&record,journal:journal)
                    _ = try verifiedBackup(record.members[index],journal:journal)
                }
            }
        } catch {return .init(batchID:record.batchID,restored:[],conflicts:[error.localizedDescription])}
        record.phase = .restoring;try journal.persist(record)
        // A journal sync is an externally observable boundary. Recheck the whole
        // group afterwards, then again inside every coordinated write accessor.
        do {for member in record.members {_ = try state(member,record:record)}}
        catch {record.phase = .recoveryNeeded;record.errors.append(error.localizedDescription);try journal.persist(record);return .init(batchID:record.batchID,restored:[],conflicts:[error.localizedDescription])}
        for index in record.members.indices {
            do {
                let member=record.members[index],source=try SecureFS.canonical(member.item.source.snapshot.url),target=try Committer.target(member.item)
                let currentState=try state(member,record:record)
                if currentState == .untouched {
                    try coordinated(source) {
                        guard try state(member,record:record)==currentState else {throw RestoreError(.conflict,"The source changed during restoration.")}
                        if try FileIdentityReader().snapshot(at:source).flags != member.item.source.snapshot.flags {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                        record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    }
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                if currentState == .duplicate {
                    guard try state(member,record:record) == .duplicate else {throw RestoreError(.conflict,"The duplicate output changed during restoration.")}
                    let stageRoot=member.stageURL!.deletingLastPathComponent(),retained=stageRoot.appendingPathComponent("\(index).restored-output")
                    try retire(index:index,record:&record,journal:journal,target:target,retained:retained,expectedState:.duplicate)
                    try coordinated(source) {
                        guard try state(record.members[index],record:record) == .untouched else {throw RestoreError(.conflict,"The original changed after duplicate retirement.")}
                        if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                        record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    }
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                if currentState == .restored {
                    try coordinated(source) {
                        guard try state(member,record:record)==currentState else {throw RestoreError(.conflict,"The source changed during restoration.")}
                        if try FileIdentityReader().snapshot(at:source).flags != member.item.source.snapshot.flags {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                        record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    }
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                let stageRoot=member.stageURL?.deletingLastPathComponent() ?? source.deletingLastPathComponent().appendingPathComponent(".RestoreGPSTime-restore-\(record.batchID.uuidString)-\(record.groupID.uuidString)")
                if !SecureFS.exists(stageRoot) {try SecureFS.privateDirectory(stageRoot)}
                let retained=stageRoot.appendingPathComponent("\(index).restored-output")
                if record.options.mode == .saveCopies || member.item.mutation.outputKind == .xmpSidecar {
                    if currentState == .changed {
                        try retire(index:index,record:&record,journal:journal,target:target,retained:retained,expectedState:.changed)
                    }
                    record.members[index].restored=true;try journal.persist(record);continue
                }

                if member.item.source.snapshot.kind == .directory {
                    _ = try verifiedBackup(member,journal:journal)
                    try coordinated(source) {
                        guard try state(member,record:record)==currentState else {throw RestoreError(.conflict,"The folder changed during restoration.")}
                        try SecureFS.applyMetadata(member.item.source.snapshot,from:member.backupURL!,to:source)
                        if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                    }
                    guard SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:source),member.item.source.snapshot) else {throw RestoreError(.verificationFailed,"Directory attributes did not restore exactly.")}
                    record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                var restoreStage=member.restoreStageURL
                if restoreStage==nil {
                    let backup=try verifiedBackup(member,journal:journal)
                    let path=stageRoot.appendingPathComponent("\(index).restore-stage")
                    record.members[index].restoreStageURL=path;try journal.persist(record)
                    _ = try SecureFS.copy(backup,from:member.backupURL!,to:path)
                    try SecureFS.applyMetadata(member.item.source.snapshot,from:member.backupURL!,to:path)
                    try await driver.restoreAttributes(member.item.source.snapshot,to:path)
                    let attributes=try FileIdentityReader().snapshot(at:path)
                    if attributes.isLocked {try SecureFS.flags(path,attributes.flags & ~UInt32(UF_IMMUTABLE))}
                    record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:path);try journal.persist(record);restoreStage=path
                }
                guard let stage=restoreStage,let expected=record.members[index].restoreFingerprint,SecureFS.exists(stage),try FileIdentityReader().fingerprint(at:stage)==expected else {throw RestoreError(.conflict,"A restore stage changed or requires manual recovery.")}
                // All member conflicts were checked before the first restoration. Check again at each write.
                let publicationState=try state(record.members[index],record:record)
                if publicationState == .changed {
                    if source.path==target.path {
                        try retire(index:index,record:&record,journal:journal,target:target,retained:stage,expectedState:.changed,swap:true)
                    } else {
                        try retire(index:index,record:&record,journal:journal,target:target,retained:retained,expectedState:.changed)
                        try coordinated(source) {
                            guard try state(record.members[index],record:record) == .notPublished else {throw RestoreError(.conflict,"The source changed before recovery publication.")}
                            try SecureFS.rename(stage,source)
                        }
                    }
                } else if publicationState == .notPublished {
                    try coordinated(source) {
                        guard try state(record.members[index],record:record) == .notPublished else {throw RestoreError(.conflict,"The source changed before recovery publication.")}
                        try SecureFS.rename(stage,source)
                    }
                }
                else {throw RestoreError(.conflict,"The recovery target changed during restoration.")}
                try coordinated(source) {
                    guard SecureFS.matches(try FileIdentityReader().fingerprint(at:source),expected,ignoreChangeTime:true) else {throw RestoreError(.conflict,"The restored source changed before its final flags.")}
                    if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                    let after=try FileIdentityReader().fingerprint(at:source)
                    guard SecureFS.matches(after,expected,ignoreChangeTime:true,flags:member.item.source.snapshot.flags) else {throw RestoreError(.verificationFailed,"Restored attributes/data did not match the retained original.")}
                }
                record.members[index].restored=true;try journal.persist(record);restored.append(source)
            } catch {conflicts.append(error.localizedDescription);record.errors.append(error.localizedDescription);record.phase = .recoveryNeeded;try journal.persist(record);break}
        }
        if conflicts.isEmpty {
            do {try CompactCleanup.restored(record);record.phase = .restored;try journal.persist(record)}
            catch {conflicts.append(error.localizedDescription);record.phase = .recoveryNeeded;record.errors.append(error.localizedDescription);try journal.persist(record)}
        }
        return .init(batchID:record.batchID,restored:restored,conflicts:conflicts)
    }
    private func coordinated(_ url:URL,_ action:()throws->Void) throws {
        var error:NSError?,result:Result<Void,Error>?
        NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:url,options:.forReplacing,error:&error) {_ in result=Result {try action()}}
        if let error {throw RestoreError(.io,"Recovery file coordination failed: \(error)")}
        guard let result else {throw RestoreError(.io,"Recovery file coordination did not grant access.")};try result.get()
    }
    private func retire(index:Int,record:inout RecoveryRecord,journal:RecoveryJournal,target:URL,retained:URL,expectedState:State,swap:Bool=false) throws {
        guard try state(record.members[index],record:record)==expectedState else {throw RestoreError(.conflict,"The output changed before retirement.")}
        let expected=try FileIdentityReader().fingerprint(at:target)
        record.members[index].recoveryRetiredURL=retained
        record.members[index].recoveryRetiredFingerprint=expected
        try journal.persist(record)
        try coordinated(target) {
            guard try state(record.members[index],record:record)==expectedState,
                  try FileIdentityReader().fingerprint(at:target)==expected else {throw RestoreError(.conflict,"The output changed at the recovery journal boundary.")}
            if expected.snapshot.kind == .directory,!((try FileManager.default.contentsOfDirectory(at:target,includingPropertiesForKeys:nil)).isEmpty) {
                throw RestoreError(.conflict,"An output folder still contains entries. Recovery will not move unrecognized contents.")
            }
            if expected.snapshot.isLocked {try SecureFS.flags(target,expected.snapshot.flags & ~UInt32(UF_IMMUTABLE))}
            try SecureFS.rename(swap ? retained:target,swap ? target:retained,swap:swap)
            try options.checkpoint(.afterMember(index))
            let displaced=try FileIdentityReader().fingerprint(at:retained)
            guard SecureFS.matches(displaced,expected,ignoreChangeTime:true,flags:expected.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {
                // Never exchange back over an occupied path. RENAME_EXCL either
                // returns the edited inode to its vacant name or preserves both.
                if !SecureFS.exists(target) {try? SecureFS.rename(retained,target)}
                throw RestoreError(.conflict,"The displaced output changed during recovery; inspect "+target.path+" and "+retained.path)
            }
        }
    }
    private func restoreSeparately(_ original:RecoveryRecord,journal:RecoveryJournal,output:URL) async throws -> RecoveryOutcome {
        var record=original,restored=[URL](),conflicts=[String]()
        do {
            if record.options.effectiveBackupMode == .none,(record.phase == .committed || record.compactCleanup != nil) {throw RestoreError(.unsupported,"No backup was selected; completed changes have no retained undo.")}
            if record.options.effectiveBackupMode != .full {
                for index in record.members.indices where record.members[index].item.mutation.outputKind == .sourceCopy {
                    _ = try state(record.members[index],record:record)
                    try prepareBackup(index:index,record:&record,journal:journal)
                    _ = try verifiedBackup(record.members[index],journal:journal)
                }
                for member in record.members {_ = try state(member,record:record)}
            }
        } catch {return .init(batchID:record.batchID,restored:[],conflicts:[error.localizedDescription])}
        let base=try SecureFS.canonical(output).appendingPathComponent(record.batchID.uuidString).appendingPathComponent(record.groupID.uuidString)
        let directory=try SecureFS.directory(base,create:true);close(directory)
        for member in record.members where member.item.mutation.outputKind == .sourceCopy {
            do {
                let backup=try verifiedBackup(member,journal:journal)
                let target=base.appendingPathComponent(member.item.source.snapshot.url.lastPathComponent)
                let staging=base.appendingPathComponent(".RestoreGPSTime-restore-\(UUID().uuidString)")
                try SecureFS.privateDirectory(staging)
                let stage=staging.appendingPathComponent(target.lastPathComponent)
                _ = try SecureFS.copy(backup,from:member.backupURL!,to:stage)
                try SecureFS.applyMetadata(member.item.source.snapshot,from:member.backupURL!,to:stage)
                try await driver.restoreAttributes(member.item.source.snapshot,to:stage)
                let verified=try FileIdentityReader().fingerprint(at:stage)
                guard verified.contentHash==member.item.source.contentHash,SecureFS.attributesEqual(verified.snapshot,member.item.source.snapshot,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.verificationFailed,"Separate restore verification failed; diagnostic stage retained.")}
                try SecureFS.rename(stage,target)
                if member.item.source.snapshot.isLocked {try SecureFS.flags(target,member.item.source.snapshot.flags)}
                restored.append(target)
                if member.compactHash != nil,let working=member.backupURL,working.lastPathComponent.hasPrefix("compact-"),SecureFS.exists(working) {
                    try CompactCleanup.remove(working,expected:try FileIdentityReader().fingerprint(at:working))
                }
            } catch {conflicts.append(error.localizedDescription)}
        }
        return .init(batchID:record.batchID,restored:restored,conflicts:conflicts)
    }
}
