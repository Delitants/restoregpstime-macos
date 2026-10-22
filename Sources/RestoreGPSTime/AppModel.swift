import Foundation
import Combine
import RestoreGPSTimeCore

struct AppInspection:Sendable {let items:[InspectedItem],excluded:[ExcludedSource]}
protocol AppBackend:Sendable {
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem]
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent>
    func cancel(_ id:UUID) async
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome
    func setRecoveryRoot(_ root:URL?) async
}
extension AppBackend {
    func setRecoveryRoot(_ root:URL?) async {}
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection {.init(items:try await inspect(urls,options:options),excluded:[])}
}
enum AppPhase:Equatable {case idle,importing,planning,ready,running,cancelling,finished,recovering,failed}
struct MediaRow:Identifiable {
    let id:String,url:URL,item:InspectedItem?
    var planned:PlannedItem?=nil
    var groupID:UUID?=nil
    var status:String
    var issue:String?=nil
}
@MainActor final class AppModel:ObservableObject {
    @Published var request:OperationRequest={var value=OperationRequest();value.dates=DatePolicy();return value}() {didSet {invalidatePreview()}}
    @Published var options=BatchOptions() {didSet {invalidatePreview()}}
    @Published var discovery:DiscoveryOptions={var value=DiscoveryOptions();value.includeFolders=false;value.enumerateRootContents=true;return value}() {didSet {invalidatePreview()}}
    @Published private(set) var phase:AppPhase = .idle
    @Published private(set) var rows=[MediaRow]()
    @Published private(set) var plan:BatchPlan?
    @Published private(set) var report:BatchReport?
    @Published private(set) var issue:String?
    @Published private(set) var progress=""
    private let backend:any AppBackend
    private var revision=0,previewRevision:Int?
    private var items=[InspectedItem](),importedURLs=[URL]()
    private var cancelWork:(()->Void)?
    private var activePlan:BatchPlan?
    var isBusy:Bool {[.importing,.planning,.running,.cancelling,.recovering].contains(phase)}
    var canApply:Bool {phase == .ready && previewRevision==revision && plan?.eligibleGroups.isEmpty==false}
    init(backend:any AppBackend) {self.backend=backend}
    private func invalidatePreview() {
        revision+=1;plan=nil;previewRevision=nil
        if phase == .planning || phase == .importing {cancelWork?();phase = .idle}
        if !isBusy {
            issue=nil
            if [.ready,.failed,.finished].contains(phase) {phase = .idle}
            if !items.isEmpty {progress="Settings changed. Preview again."}
        }
        rows=rows.filter {row in row.item.map {item in row.id==item.snapshot.id.physicalKey} ?? true}.map {row in
            var value=row;value.planned=nil;value.groupID=nil
            if ["eligible","blocked"].contains(value.status) {value.status="imported";value.issue=nil}
            return value
        }
    }
    func importURLs(_ urls:[URL]) async {
        guard ![.running,.cancelling,.recovering].contains(phase) else {return}
        cancelWork?();invalidatePreview();issue=nil
        importedURLs=Array(Set(importedURLs+urls.map(\.standardizedFileURL))).sorted {$0.path<$1.path}
        options.importRoots=importedURLs
        let ticket=revision;phase = .importing;progress="Reading file metadata…"
        let backend=self.backend,roots=importedURLs
        var scope=discovery
        scope.excludedRoots+=[options.mode == .saveCopies ? options.outputRoot:nil,options.recoveryRoot].compactMap {$0}
        let task=Task {try await backend.inspectDetailed(roots,options:scope)};cancelWork={task.cancel()}
        do {
            let result=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            guard ticket==revision,!task.isCancelled else {return}
            items=result.items
            rows=result.items.map {.init(id:$0.snapshot.id.physicalKey,url:$0.snapshot.url,item:$0,status:"imported")}
            rows+=result.excluded.map {.init(id:"excluded:"+$0.url.standardizedFileURL.path,url:$0.url,item:nil,status:"excluded",issue:$0.reason)}
            phase = .idle;progress="\(result.items.count) items imported; \(result.excluded.count) excluded"
        } catch {if ticket==revision {phase = task.isCancelled ? .idle:.failed;issue=task.isCancelled ? nil:error.localizedDescription;progress=task.isCancelled ? "Import cancelled.":"Import needs attention."}}
        if ticket==revision {cancelWork=nil}
    }
    func preview() async {
        guard !isBusy else {return}
        guard !items.isEmpty else {issue="Add files or a folder first.";return}
        plan=nil;previewRevision=nil;issue=nil;phase = .planning;progress="Building a preview…"
        let ticket=revision,backend=self.backend,inputs=items,request=self.request,options=self.options
        let task=Task {try await backend.preview(items:inputs,request:request,options:options)};cancelWork={task.cancel()}
        do {
            let value=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            guard ticket==revision,!task.isCancelled else {return}
            plan=value;previewRevision=ticket;show(value);phase = .ready
            progress="\(value.eligibleGroups.count) eligible asset groups; \(value.groups.filter {$0.eligibility == .blocked}.count) blocked"
        } catch {if ticket==revision {phase = task.isCancelled ? .idle:.failed;issue=task.isCancelled ? nil:error.localizedDescription;progress=task.isCancelled ? "Preview cancelled.":"Preview needs attention."}}
        if ticket==revision {cancelWork=nil}
    }
    private func show(_ plan:BatchPlan) {
        let known=Dictionary(uniqueKeysWithValues:items.map {($0.snapshot.id.physicalKey,$0)})
        let excluded=rows.filter {$0.item==nil}
        rows=plan.groups.flatMap {group in group.items.map {item in
            MediaRow(id:item.name.sourceKey,url:item.source.snapshot.url,item:known[item.source.snapshot.id.physicalKey],planned:item,groupID:group.id,status:group.eligibility.rawValue,issue:group.blockingReasons.isEmpty ? nil:group.blockingReasons.joined(separator:"\n"))
        }}
        rows+=excluded
    }
    func applyPreview() async {
        guard canApply,let frozen=plan else {return}
        activePlan=frozen;plan=nil;previewRevision=nil;phase = .running;issue=nil;progress="Starting batch…"
        var pending=[UUID:RowUpdate]()
        var lastPublication:UInt64=0,lastYield=DispatchTime.now().uptimeNanoseconds
        for await event in await backend.execute(frozen) {
            switch event {
            case .started:break
            case .progress(let id,let text):
                progress=text
                pending[id] = .init(status:"running",issue:nil)
            case .rejected(let validation):issue=validation.conflicts.map { $0.error.detail }.joined(separator:"\n")
            case .group(let result):pending[result.groupID]=RowUpdate(result)
            case .finished(let result):
                report=result
                for group in result.results {pending[group.groupID]=RowUpdate(group)}
                publish(pending);pending.removeAll(keepingCapacity:true)
                progress=result.cancelled ? "Cancelled after the current protected group finished.":(result.success ? "Batch completed.":"Batch finished with results to review.")
            }
            let now=DispatchTime.now().uptimeNanoseconds
            if !pending.isEmpty,now-lastPublication>=100_000_000 {publish(pending);pending.removeAll(keepingCapacity:true);lastPublication=now}
            if now-lastYield>=8_000_000 {await Task.yield();lastYield=DispatchTime.now().uptimeNanoseconds}
        }
        if !pending.isEmpty {publish(pending)}
        phase = .finished;activePlan=nil
    }
    private struct RowUpdate {
        let status:String,issue:String?
        init(status:String,issue:String?) {self.status=status;self.issue=issue}
        init(_ result:GroupResult) {status=result.status.rawValue;issue=result.errors.isEmpty ? nil:result.errors.joined(separator:"\n")}
    }
    private func publish(_ updates:[UUID:RowUpdate]) {
        // One linear projection and one Published assignment, independent of the
        // number of completed groups. Interim events are keyed and coalesced.
        rows=rows.map {value in
            guard let id=value.groupID,let update=updates[id] else {return value}
            var row=value;row.status=update.status;if let issue=update.issue {row.issue=issue};return row
        }
    }
    func cancel() {
        if let activePlan,phase == .running || phase == .cancelling {
            phase = .cancelling;progress="Finishing the current protected group…"
            Task {await backend.cancel(activePlan.id)}
        } else if phase == .importing || phase == .planning {
            cancelWork?();revision+=1;plan=nil;previewRevision=nil;phase = .idle;progress="Cancelled."
        }
    }
    func restore(batchID:UUID,choice:RecoveryChoice) async {
        guard !isBusy else {return};phase = .recovering;issue=nil;progress="Restoring verified originals…"
        do {
            await backend.setRecoveryRoot(options.recoveryRoot)
            let result=try await backend.restore(batchID:batchID,choice:choice)
            if !result.isComplete {issue=result.conflicts.joined(separator:"\n")}
            progress=result.isComplete ? "Recovery completed.":"Recovery has conflicts to review."
        } catch {issue=error.localizedDescription;progress="Recovery stopped; retained originals remain available."}
        phase = .finished
    }
    func clear() {guard !isBusy else {return};invalidatePreview();items=[];importedURLs=[];rows=[];report=nil;issue=nil;progress=""}
    func presentError(_ error:Error) {issue=error.localizedDescription}
}
