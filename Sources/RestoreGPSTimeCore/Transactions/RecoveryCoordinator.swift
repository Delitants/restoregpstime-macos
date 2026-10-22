import Foundation
import Darwin

public struct RecoveryCoordinator:Sendable {
    let root:URL
    let driver:any MutationDriver
    public init(root:URL,driver:any MutationDriver) {self.root=root;self.driver=driver}
    public func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {
        let worker=Task.detached(priority:.userInitiated) {try await restoreBlocking(batchID:batchID,choice:choice)}
        return try await worker.value
    }
    private func restoreBlocking(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {
        let journal=try RecoveryJournal(root:root,batchID:batchID)
        var restored=[URL](),conflicts=[String]()
        var ownRestoredPaths=[URL]()
        let records=try journal.records().sorted {a,b in
            let ad=a.members.allSatisfy {$0.item.source.snapshot.kind == .directory},bd=b.members.allSatisfy {$0.item.source.snapshot.kind == .directory}
            if ad != bd {return !ad}
            if ad {return a.members[0].item.source.snapshot.url.path.count>b.members[0].item.source.snapshot.url.path.count}
            return a.groupID.uuidString<b.groupID.uuidString
        }
        for var record in records {
            for index in record.members.indices where record.members[index].item.source.snapshot.kind == .directory {
                let member=record.members[index],source=member.item.source.snapshot
                if record.options.mode == .modifyInPlace,ownRestoredPaths.contains(where:{$0.path != source.url.path && BatchPlanner.isWithin($0,source.url)}) {
                    let current=try FileIdentityReader().fingerprint(at:source.url)
                    let expected=member.after?.snapshot ?? source
                    if current.snapshot.id.physicalKey==source.id.physicalKey,SecureFS.stableDirectoryAttributes(current.snapshot,expected),current.snapshot.creationDate==expected.creationDate {
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
        if let restored=member.restoreFingerprint,SecureFS.exists(source) {
            let current=try reader.fingerprint(at:source)
            if SecureFS.matches(current,restored,ignoreChangeTime:true,flags:member.item.source.snapshot.flags) || SecureFS.matches(current,restored,ignoreChangeTime:true) {return .restored}
        }
        if record.options.mode == .modifyInPlace && member.item.mutation.outputKind == .sourceCopy && SecureFS.exists(source) {
            let current=try reader.fingerprint(at:source)
            let originalMatches=SecureFS.matches(current,member.item.source) || (member.item.mutation.explicitlyUnlocks && member.item.source.snapshot.isLocked && member.step != .pending && SecureFS.matches(current,member.item.source,ignoreChangeTime:true,flags:member.item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)))
            if originalMatches {
                if source.path != target.path,let expected=member.staged,SecureFS.exists(target),SecureFS.matches(try reader.fingerprint(at:target),expected,ignoreChangeTime:true,flags:finalFlags(member)) {return .duplicate}
                return .untouched
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
        throw RestoreError(.conflict,"An expected original/output is missing; originals remain retained for separate-folder recovery.")
    }
    private func verifiedBackup(_ member:RecoveryMember,journal:RecoveryJournal) throws -> SourceFingerprint {
        guard let url=member.backupURL,BatchPlanner.isWithin(url,journal.batchDirectory.appendingPathComponent("originals")) else {throw RestoreError(.recoveryNeeded,"A verified retained original is unavailable.")}
        let fingerprint=try FileIdentityReader().fingerprint(at:url)
        guard fingerprint.snapshot.kind==member.item.source.snapshot.kind,fingerprint.contentHash==member.backupHash,fingerprint.contentHash==member.item.source.contentHash,fingerprint.snapshot.xattrHashes==member.item.source.snapshot.xattrHashes else {throw RestoreError(.verificationFailed,"The retained original changed; recovery stopped.")}
        return fingerprint
    }
    func restoreGroup(_ original:RecoveryRecord,journal:RecoveryJournal) async throws -> RecoveryOutcome {
        var record=original,states=[State](),conflicts=[String](),restored=[URL]()
        do {
            for member in record.members {
                let current=try state(member,record:record);states.append(current)
                if record.options.mode == .modifyInPlace && member.item.mutation.outputKind == .sourceCopy && (current == .changed || current == .notPublished) {_ = try verifiedBackup(member,journal:journal)}
            }
        } catch {return .init(batchID:record.batchID,restored:[],conflicts:[error.localizedDescription])}
        record.phase = .restoring;try journal.persist(record)
        for index in record.members.indices {
            do {
                let member=record.members[index],source=try SecureFS.canonical(member.item.source.snapshot.url),target=try Committer.target(member.item)
                if states[index] == .untouched {
                    if try FileIdentityReader().snapshot(at:source).flags != member.item.source.snapshot.flags {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                    record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                if states[index] == .duplicate {
                    guard try state(member,record:record) == .duplicate else {throw RestoreError(.conflict,"The duplicate output changed during restoration.")}
                    let stageRoot=member.stageURL!.deletingLastPathComponent(),retained=stageRoot.appendingPathComponent("\(index).restored-output")
                    let current=try FileIdentityReader().snapshot(at:target)
                    if current.isLocked {try SecureFS.flags(target,current.flags & ~UInt32(UF_IMMUTABLE))}
                    try SecureFS.rename(target,retained)
                    if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                    record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                if states[index] == .restored {
                    if try FileIdentityReader().snapshot(at:source).flags != member.item.source.snapshot.flags {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                    record.members[index].restoreFingerprint=try FileIdentityReader().fingerprint(at:source)
                    record.members[index].restored=true;try journal.persist(record);restored.append(source);continue
                }
                let stageRoot=member.stageURL?.deletingLastPathComponent() ?? source.deletingLastPathComponent().appendingPathComponent(".RestoreGPSTime-restore-\(record.batchID.uuidString)-\(record.groupID.uuidString)")
                if !SecureFS.exists(stageRoot) {try SecureFS.privateDirectory(stageRoot)}
                let retained=stageRoot.appendingPathComponent("\(index).restored-output")
                if record.options.mode == .saveCopies || member.item.mutation.outputKind == .xmpSidecar {
                    if states[index] == .changed {let current=try FileIdentityReader().snapshot(at:target);if current.isLocked {try SecureFS.flags(target,current.flags & ~UInt32(UF_IMMUTABLE))};try SecureFS.rename(target,retained)}
                    record.members[index].restored=true;try journal.persist(record);continue
                }

                if member.item.source.snapshot.kind == .directory {
                    _ = try verifiedBackup(member,journal:journal)
                    try SecureFS.applyMetadata(member.item.source.snapshot,from:member.backupURL!,to:source)
                    if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
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
                let currentState=try state(record.members[index],record:record)
                if currentState == .changed {
                    let current=try FileIdentityReader().snapshot(at:target)
                    if current.isLocked {try SecureFS.flags(target,current.flags & ~UInt32(UF_IMMUTABLE))}
                    if source.path==target.path {try SecureFS.rename(stage,source,swap:true)}
                    else {
                        try SecureFS.rename(target,retained)
                        try SecureFS.rename(stage,source)
                    }
                } else if currentState == .notPublished {try SecureFS.rename(stage,source)}
                else {throw RestoreError(.conflict,"The recovery target changed during restoration.")}
                if member.item.source.snapshot.isLocked {try SecureFS.flags(source,member.item.source.snapshot.flags)}
                let after=try FileIdentityReader().fingerprint(at:source)
                guard SecureFS.matches(after,expected,ignoreChangeTime:true,flags:member.item.source.snapshot.flags) else {throw RestoreError(.verificationFailed,"Restored attributes/data did not match the retained original.")}
                record.members[index].restored=true;try journal.persist(record);restored.append(source)
            } catch {conflicts.append(error.localizedDescription);record.errors.append(error.localizedDescription);record.phase = .recoveryNeeded;try journal.persist(record);break}
        }
        if conflicts.isEmpty {record.phase = .restored;try journal.persist(record)}
        return .init(batchID:record.batchID,restored:restored,conflicts:conflicts)
    }
    private func restoreSeparately(_ record:RecoveryRecord,journal:RecoveryJournal,output:URL) async throws -> RecoveryOutcome {
        var restored=[URL](),conflicts=[String]()
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
            } catch {conflicts.append(error.localizedDescription)}
        }
        return .init(batchID:record.batchID,restored:restored,conflicts:conflicts)
    }
}
