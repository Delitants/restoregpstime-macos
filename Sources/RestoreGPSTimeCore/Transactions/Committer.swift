import Foundation
import Darwin

public struct Committer:Sendable {
    let options:RunOptions
    public init(options:RunOptions=RunOptions()) {self.options=options}
    public func commit(group:PlannedGroup,stages:StageResult,journal:RecoveryJournal) async throws -> GroupResult {
        var record=stages.record
        record.phase = .committing;try journal.persist(record);try options.checkpoint(.persisted(.committing))
        for index in record.members.indices {
            let item=record.members[index].item,source=try SecureFS.canonical(item.source.snapshot.url),target=try Self.target(item)
            var coordinatorError:NSError?,operation:Result<Void,Error>?
            let accessor:()->Void={operation=Result {try self.commitMember(index:index,record:&record,journal:journal,source:source,target:target,expectedSources:stages.expectedSources,ownedDirectories:stages.ownedDirectories)}}
            let coordinator=NSFileCoordinator(filePresenter:nil)
            if record.options.mode == .modifyInPlace && item.mutation.outputKind == .sourceCopy {
                coordinator.coordinate(writingItemAt:source,options:.forReplacing,error:&coordinatorError) {_ in accessor()}
            } else {coordinator.coordinate(writingItemAt:target,options:.forReplacing,error:&coordinatorError) {_ in accessor()}}
            if let error=coordinatorError {throw RestoreError(.io,"File coordination failed: \(error)")}
            guard let operation else {throw RestoreError(.io,"File coordination did not grant access.")};try operation.get()
            try options.checkpoint(.afterMember(index))
        }
        record.phase = .committed;try journal.persist(record);try options.checkpoint(.persisted(.committed))
        return .init(groupID:group.id,status:.committed,outputs:record.members.compactMap {$0.after?.snapshot.url},recoveryURL:journal.recordURL(groupID:group.id))
    }
    static func target(_ item:PlannedItem) throws -> URL {
        guard let anchor=item.destinationAnchor,BatchPlanner.isWithin(item.name.finalURL,anchor.requestedURL) else {throw RestoreError(.conflict,"Destination is outside its frozen parent.")}
        let current=try FileIdentityReader().snapshot(at:anchor.requestedURL)
        guard current.kind == .directory,current.id.physicalKey==anchor.identity.physicalKey,(try FileSystemPath.canonicalDirectory(anchor.requestedURL)).path==anchor.resolvedURL.path else {throw RestoreError(.conflict,"Destination parent identity changed.")}
        let relative=String(item.name.finalURL.path.dropFirst(anchor.requestedURL.path.count)).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        return anchor.resolvedURL.appendingPathComponent(relative)
    }
    private func commitMember(index:Int,record:inout RecoveryRecord,journal:RecoveryJournal,source:URL,target:URL,expectedSources:[String:SourceFingerprint],ownedDirectories:[String:SourceID]) throws {
        let item=record.members[index].item,reader=FileIdentityReader()
        guard let stage=record.members[index].stageURL,let expected=record.members[index].staged,try reader.fingerprint(at:stage)==expected else {throw RestoreError(.conflict,"The verified stage changed before commit.")}
        try createParents(target.deletingLastPathComponent(),record:&record,journal:journal)
        let inPlace=record.options.mode == .modifyInPlace && item.mutation.outputKind == .sourceCopy
        if inPlace {
            let actual=try reader.fingerprint(at:source)
            guard actual==(expectedSources[item.source.snapshot.id.physicalKey] ?? item.source) else {throw RestoreError(.conflict,"The original changed immediately before commit.")}
        }
        func persist(_ step:CommitStep) throws {record.members[index].step=step;try journal.persist(record);try options.checkpoint(.persistedStep(step,index:index))}
        if inPlace && item.source.snapshot.isLocked {
            guard item.mutation.explicitlyUnlocks else {throw RestoreError(.conflict,"Unlock was not approved in preview.")}
            try persist(.unlockPending);try SecureFS.flags(source,item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE));try persist(.unlocked)
        }
        if item.source.snapshot.kind == .directory {
            // Directory attributes run after descendants; a directory hierarchy is never exchanged.
            guard !item.mutation.changesContent else {throw RestoreError(.unsupported,"Directories cannot contain embedded metadata writes.")}
            let targetExists=SecureFS.exists(target)
            if !inPlace && targetExists {
                let current=try reader.snapshot(at:target)
                guard let owned=ownedDirectories[target.path] ?? record.createdDirectories[target.path],owned.physicalKey==current.id.physicalKey else {throw RestoreError(.conflict,"A directory destination already exists outside this batch.")}
            }
            try persist(.directoryPending)
            if !inPlace && !targetExists {
                record.directoryIntents.append(target);try journal.persist(record)
                let fd=try SecureFS.directory(target.deletingLastPathComponent());defer {close(fd)}
                guard mkdirat(fd,target.lastPathComponent,0o755)==0 else {throw SecureFS.error("Create directory without replacing an existing path")}
                record.createdDirectories[target.path]=try reader.snapshot(at:target).id;try journal.persist(record)
            }
            try SecureFS.applyMetadata(expected.snapshot,from:stage,to:target)
        } else if inPlace && source.path==target.path {
            try persist(.swapPending);try SecureFS.rename(stage,target,swap:true);try persist(.swapped)
            let held=try reader.fingerprint(at:stage)
            guard SecureFS.matches(held,item.source,ignoreChangeTime:true,flags:item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.recoveryNeeded,"The exchanged original differs from preview; retained evidence needs recovery.")}
        } else {
            let caseOnly=inPlace && item.name.needsTemporaryRename
            if caseOnly {
                try persist(.retirePending);try SecureFS.rename(source,record.members[index].heldOriginalURL!);try persist(.retired)
            }
            try persist(.publishPending);try SecureFS.rename(stage,target);try persist(.published)
            if inPlace && !caseOnly {
                // Recheck before retiring the old name; a concurrent edit is retained rather than removed.
                let current=try reader.fingerprint(at:source)
                guard SecureFS.matches(current,item.source,ignoreChangeTime:item.source.snapshot.isLocked,flags:item.source.snapshot.flags & ~UInt32(UF_IMMUTABLE)) else {throw RestoreError(.conflict,"The source changed while publishing its new name.")}
                try persist(.retirePending);try SecureFS.rename(source,record.members[index].heldOriginalURL!);try persist(.retired)
            }
        }
        var flags=expected.snapshot.flags
        let desiredLock=item.mutation.finder.compactMap {mutation->Bool? in if case .locked(let value)=mutation {return value};return nil}.last ?? item.source.snapshot.isLocked
        if desiredLock {flags |= UInt32(UF_IMMUTABLE)} else {flags &= ~UInt32(UF_IMMUTABLE)}
        try persist(.flagsPending)
        if flags != (try reader.snapshot(at:target).flags) {try SecureFS.flags(target,flags)}
        let after=try reader.fingerprint(at:target)
        if item.source.snapshot.kind != .directory {
            guard SecureFS.matches(after,expected,ignoreChangeTime:true,flags:flags) else {throw RestoreError(.recoveryNeeded,"The committed file does not match the verified stage.")}
        } else {
            guard SecureFS.attributesEqual(after.snapshot,expected.snapshot,flags:flags) else {throw RestoreError(.recoveryNeeded,"Committed directory attributes do not match the verified stage.")}
        }
        record.members[index].after=after;try persist(.complete)
    }
    private func createParents(_ parent:URL,record:inout RecoveryRecord,journal:RecoveryJournal) throws {
        let ancestor=try FileSystemPath.canonicalDirectory(BatchPlanner.existingParent(of:parent))
        let prefix=ancestor.path.hasSuffix("/") ? ancestor.path:ancestor.path+"/"
        let relative=parent.path==ancestor.path ? "":String(parent.path.dropFirst(prefix.count))
        var current=ancestor
        for component in relative.split(separator:"/") {
            current=current.appendingPathComponent(String(component))
            record.directoryIntents.append(current);try journal.persist(record)
            let fd=try SecureFS.directory(current.deletingLastPathComponent());defer {close(fd)}
            guard mkdirat(fd,current.lastPathComponent,0o755)==0 else {throw SecureFS.error("Create reserved output hierarchy")}
            let snapshot=try FileIdentityReader().snapshot(at:current)
            record.createdDirectories[current.path]=snapshot.id;try journal.persist(record)
        }
    }
}
