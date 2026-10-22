import Foundation

public enum TransactionPoint:Equatable,Sendable {case persisted(RecoveryPhase),persistedStep(CommitStep,index:Int),beforeBackup(String),beforeStage(String),beforeCommit,afterMember(Int),beforeJournalSync}
public struct SimulatedInterruption:Error,Sendable {public init() {}}
public struct RunOptions:Sendable {
    public let checkpoint:@Sendable (TransactionPoint) throws -> Void
    public init(checkpoint:@escaping @Sendable (TransactionPoint) throws -> Void={_ in}) {self.checkpoint=checkpoint}
}
public actor BatchExecutor {
    let driver:any MutationDriver
    let validator:PlanValidator
    let notifier:any FinderNotifying
    private var tasks=[UUID:Task<Void,Never>]()
    private var cancelled=Set<UUID>()
    public init(driver:any MutationDriver,validator:PlanValidator,notifier:any FinderNotifying=FinderNotifier()) {self.driver=driver;self.validator=validator;self.notifier=notifier}
    public nonisolated func execute(_ plan:BatchPlan,options:RunOptions=RunOptions())->AsyncStream<BatchEvent> {
        AsyncStream {continuation in Task {await self.start(plan,options:options,continuation:continuation)}}
    }
    private func start(_ plan:BatchPlan,options:RunOptions,continuation:AsyncStream<BatchEvent>.Continuation) {
        guard tasks.isEmpty else {continuation.yield(.rejected(.init(conflicts:[.init(groupID:nil,sourceKey:nil,error:.init(.conflict,"A batch is already running."))])));continuation.finish();return}
        tasks[plan.id]=Task {await run(plan,options:options,continuation:continuation)}
    }
    public func cancel(batchID:UUID) {cancelled.insert(batchID);tasks[batchID]?.cancel()}
    private func run(_ plan:BatchPlan,options:RunOptions,continuation:AsyncStream<BatchEvent>.Continuation) async {
        let started=Date();var results=[GroupResult]()
        defer {tasks[plan.id]=nil;cancelled.remove(plan.id);continuation.finish()}
        continuation.yield(.started(plan.id,totalGroups:plan.groups.count))
        let validation=await validator.revalidate(plan)
        if !validation.isValid {continuation.yield(.rejected(validation));results=plan.groups.map {.init(groupID:$0.id,status:.failed,errors:validation.conflicts.map {$0.error.detail})};continuation.yield(.finished(.init(plan:plan,startedAt:started,results:results,cancelled:Task.isCancelled)));return}
        if plan.options.mode == .modifyInPlace,plan.request.isFinderNotificationOnly,plan.groups.allSatisfy({$0.items.allSatisfy {$0.mutation.isFinderNotificationOnly && $0.name.finalURL.standardizedFileURL.path==$0.source.snapshot.url.standardizedFileURL.path}}) {
            for group in plan.groups {
                let result:GroupResult
                if group.eligibility != .eligible {result = .init(groupID:group.id,status:group.eligibility == .excluded ? .excluded:.blocked,errors:group.blockingReasons)}
                else if Task.isCancelled {result = .init(groupID:group.id,status:.cancelled)}
                else {
                    do {
                        try SourceRevalidator().validate(group)
                        let urls=group.items.map {$0.source.snapshot.url}
                        await notifier.notify(changed:urls)
                        result = .init(groupID:group.id,status:.committed,outputs:urls)
                    } catch {result = .init(groupID:group.id,status:.failed,errors:[error.localizedDescription])}
                }
                results.append(result);continuation.yield(.group(result))
            }
            continuation.yield(.finished(.init(plan:plan,startedAt:started,results:results,cancelled:Task.isCancelled)));return
        }
        guard let root=plan.options.recoveryRoot else {
            results=plan.groups.map {.init(groupID:$0.id,status:.failed,errors:["Choose a recovery folder for retained transaction evidence."])}
            continuation.yield(.finished(.init(plan:plan,startedAt:started,results:results,cancelled:false)));return
        }
        var activeJournal:RecoveryJournal?,interrupted=false
        do {
            let journal=try RecoveryJournal(root:root,batchID:plan.id,checkpoint:options.checkpoint)
            activeJournal=journal
            // Descendants finish before selected directory attributes.
            var directoryOverrides=[String:SourceFingerprint](),ownedDirectories=[String:SourceID]()
            let groupOrder=Dictionary(uniqueKeysWithValues:plan.groups.enumerated().map {($0.element.id,$0.offset)})
            let groups=plan.groups.sorted {a,b in
                let ad=a.items.allSatisfy {$0.source.snapshot.kind == .directory},bd=b.items.allSatisfy {$0.source.snapshot.kind == .directory}
                if ad != bd {return !ad};if ad && a.items[0].source.snapshot.url.path.count != b.items[0].source.snapshot.url.path.count {return a.items[0].source.snapshot.url.path.count>b.items[0].source.snapshot.url.path.count}
                return (groupOrder[a.id] ?? 0)<(groupOrder[b.id] ?? 0)
            }
            // Retain selected directory metadata before any child can change its dates.
            if plan.options.mode == .modifyInPlace {
                for group in groups where group.eligibility == .eligible && group.items.allSatisfy({$0.source.snapshot.kind == .directory}) {
                    var directoryRecord=RecoveryRecord(batchID:plan.id,group:group,options:plan.options)
                    try SourceRevalidator().validate(group)
                    try journal.persist(directoryRecord);try options.checkpoint(.persisted(.prepared))
                    try BackupStore().prepare(&directoryRecord,journal:journal,options:options)
                    directoryRecord.phase = .backedUp;try journal.persist(directoryRecord);try options.checkpoint(.persisted(.backedUp))
                }
                let directories=try journal.records().filter {$0.phase == .backedUp && $0.members.allSatisfy {$0.item.source.snapshot.kind == .directory}}.sorted {$0.members[0].item.source.snapshot.url.path.count<$1.members[0].item.source.snapshot.url.path.count}
                for var record in directories {
                    let updated=try DirectoryLockCoordinator().unlockPrepared(&record,journal:journal,options:options)
                    directoryOverrides.merge(updated,uniquingKeysWith:{$1})
                }
            }
            let hasSelectedDirectories=groups.contains {$0.items.contains {$0.source.snapshot.kind == .directory}}
            for group in groups {
                let result:GroupResult
                if group.eligibility != .eligible {result = .init(groupID:group.id,status:group.eligibility == .excluded ? .excluded:.blocked,errors:group.blockingReasons)}
                else if Task.isCancelled || cancelled.contains(plan.id) {result = .init(groupID:group.id,status:.cancelled)}
                else {
                    var record=RecoveryRecord(batchID:plan.id,group:group,options:plan.options)
                    do {
                        try SourceRevalidator().validate(group,overrides:directoryOverrides)
                        if let prepared=try journal.record(groupID:group.id),prepared.phase == .backedUp {record=prepared}
                        else {
                            try journal.persist(record);try options.checkpoint(.persisted(.prepared))
                            continuation.yield(.progress(group.id,phase:"Retaining originals"))
                            try BackupStore().prepare(&record,journal:journal,options:options)
                            record.phase = .backedUp;try journal.persist(record);try options.checkpoint(.persisted(.backedUp))
                        }
                        continuation.yield(.progress(group.id,phase:"Staging and verifying"))
                        try await StageStore().prepare(&record,journal:journal,driver:driver,options:options)
                        try options.checkpoint(.beforeCommit);try Task.checkCancellation();try SourceRevalidator().validate(group,overrides:directoryOverrides)
                        continuation.yield(.progress(group.id,phase:"Committing"))
                        // Protected commits finish independently of cancellation of the batch task.
                        let staged=StageResult(record:record,expectedSources:directoryOverrides,ownedDirectories:ownedDirectories)
                        result=try await Task.detached {try await Committer(options:options).commit(group:group,stages:staged,journal:journal)}.value
                    } catch is SimulatedInterruption {
                        interrupted=true
                        result = .init(groupID:group.id,status:.recoveryNeeded,errors:["Injected process interruption; journal retained."],recoveryURL:journal.recordURL(groupID:group.id))
                    } catch {
                        let cancellation=error is CancellationError || (error as? RestoreError)?.code == .cancelled
                        if cancellation {cancelled.insert(plan.id)}
                        var status:GroupStatus=cancellation ? .cancelled:.failed
                        var messages=[error.localizedDescription]
                        do {
                            if var latest=try journal.record(groupID:group.id) {
                                let mayHaveMutated=latest.phase == .committing || latest.phase == .committed
                                latest.errors+=messages;latest.phase=mayHaveMutated ? .recoveryNeeded:(cancellation ? .cancelled:.failed);try journal.persist(latest)
                                if mayHaveMutated {
                                    let recoveryDriver=driver,restoreRecord=latest
                                    let recovery=try await Task.detached {try await RecoveryCoordinator(root:root,driver:recoveryDriver).restoreGroup(restoreRecord,journal:journal)}.value
                                    if !recovery.isComplete {status = .recoveryNeeded;messages+=recovery.conflicts}
                                }
                            }
                        } catch {status = .recoveryNeeded;messages.append("Recovery journal could not be updated: "+error.localizedDescription)}
                        result = .init(groupID:group.id,status:status,errors:messages,recoveryURL:journal.recordURL(groupID:group.id))
                    }
                }
                if hasSelectedDirectories,let updated=try? SourceRevalidator().refreshedDirectoryOverrides(plan:plan,journal:journal,previous:directoryOverrides) {directoryOverrides=updated}
                if let record=try? journal.record(groupID:group.id) {ownedDirectories.merge(record.createdDirectories,uniquingKeysWith:{$1})}
                if result.status == .committed,group.items.contains(where:{$0.mutation.finder.contains(.notify)}) {await notifier.notify(changed:result.outputs)}
                results.append(result);continuation.yield(.group(result))
            }
        } catch {
            if error is SimulatedInterruption {interrupted=true}
            results+=plan.groups.filter {group in !results.contains(where:{$0.groupID==group.id})}.map {.init(groupID:$0.id,status:interrupted ? .recoveryNeeded:.failed,errors:[error.localizedDescription])}
        }
        if let journal=activeJournal,!interrupted {
            do {
                let recoveryDriver=driver
                let outcomes=try await Task.detached {try await DirectoryLockCoordinator().restoreUnfinished(journal:journal,driver:recoveryDriver)}.value
                for (id,outcome) in outcomes where !outcome.isComplete {
                    if let index=results.firstIndex(where:{$0.groupID==id}) {
                        let old=results[index]
                        results[index] = .init(groupID:id,status:.recoveryNeeded,outputs:old.outputs,errors:old.errors+outcome.conflicts,recoveryURL:journal.recordURL(groupID:id))
                    }
                }
            } catch {
                results=results.map {value in value.status == .committed ? value:.init(groupID:value.groupID,status:.recoveryNeeded,outputs:value.outputs,errors:value.errors+["Directory recovery requires attention: "+error.localizedDescription],recoveryURL:value.recoveryURL)}
            }
        }
        continuation.yield(.finished(.init(plan:plan,startedAt:started,results:results,cancelled:cancelled.contains(plan.id) || Task.isCancelled)))
    }
}
