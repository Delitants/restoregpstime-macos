import Foundation
import Combine
import RestoreGPSTimeCore

struct AppInspection:Sendable {let items:[InspectedItem],excluded:[ExcludedSource]}
protocol AppBackend:Sendable {
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem]
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> AppInspection
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> BatchPlan
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent>
    func cancel(_ id:UUID) async
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome
    func restore(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?) async throws -> RecoveryOutcome
    func setRecoveryRoot(_ root:URL?) async
}
extension AppBackend {
    func restore(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?) async throws -> RecoveryOutcome {
        guard selectedSourceKeys == nil else {throw RestoreError(.unsupported,"This recovery backend does not support selected files.")}
        return try await restore(batchID:batchID,choice:choice)
    }
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> AppInspection {try await inspectDetailed(urls,options:options)}
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> BatchPlan {try await preview(items:items,request:request,options:options)}
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
struct BlockingReasonSummary:Identifiable,Equatable {
    let reason:String,groupCount:Int
    var id:String {reason}
}
@MainActor final class AppModel:ObservableObject {
    @Published var request:OperationRequest={var value=OperationRequest();var dates=DatePolicy();dates.automaticTimeZone=true;value.dates=dates;return value}() {didSet {if request != oldValue {invalidatePreview();settingsDidChange?()}}}
    @Published var options:BatchOptions={var value=BatchOptions();value.backupMode = .metadata;return value}() {didSet {
        if options != oldValue {
            var bindingOnly=oldValue;bindingOnly.outputRoot=options.outputRoot
            if !(componentWorkflow && plan?.destinationPending==true && bindingOnly==options) {invalidatePreview()}
            settingsDidChange?()
        }
    }}
    @Published var discovery:DiscoveryOptions={var value=DiscoveryOptions();value.includeFolders=false;value.enumerateRootContents=true;return value}() {didSet {invalidatePreview();settingsDidChange?()}}
    @Published private(set) var phase:AppPhase = .idle
    @Published private(set) var rows=[MediaRow]()
    @Published private(set) var plan:BatchPlan?
    @Published private(set) var report:BatchReport?
    @Published private(set) var issue:String?
    @Published private(set) var progress=""
    @Published private(set) var preparationProgress:PreparationProgress?
    @Published private(set) var blockedReasons=[BlockingReasonSummary]()
    var settingsDidChange:(()->Void)?
    var activePreviewComponent:PreviewComponent = .dates
    private var componentWorkflow=false
    private var componentPlans=[PreviewComponent:BatchPlan]()
    private var compositionGeneration=0
    var pendingPreviewComponents:[PreviewComponent] {PreviewComponent.allCases.filter {component in
        guard component.isSelected(in:request) else {return false}
        guard let cached=componentPlans[component],cached.request==component.request(from:request),cached.options.mode==options.mode else {return true}
        return component == .dates && (cached.options.referenceRoot != options.referenceRoot || cached.options.allowReferenceBasenameFallback != options.allowReferenceBasenameFallback)
    }}
    var selectedChangeSummary:String {let names=PreviewComponent.allCases.filter {$0.isSelected(in:request)}.map(\.title);return names.isEmpty ? "No changes selected":"Selected changes: "+names.joined(separator:" • ")}
    var outputDestinationPending:Bool {options.mode == .saveCopies && options.outputRoot==nil}
    private var lastPreparationPublication:UInt64=0
    private let backend:any AppBackend
    private var revision=0,previewRevision:Int?
    private var items=[InspectedItem](),importedURLs=[URL]()
    private var cancelWork:(()->Void)?
    private var activePlan:BatchPlan?
    var isBusy:Bool {[.importing,.planning,.running,.cancelling,.recovering].contains(phase)}
    var canApply:Bool {phase == .ready && previewRevision==revision && plan?.eligibleGroups.isEmpty==false}
    init(backend:any AppBackend) {self.backend=backend}
    private func invalidatePreview() {
        revision+=1;compositionGeneration+=1;plan=nil;previewRevision=nil
        preparationProgress=nil;blockedReasons=[]
        if phase == .planning || phase == .importing {cancelWork?();phase = .idle}
        if !isBusy {
            issue=nil
            if [.ready,.failed,.finished].contains(phase) {phase = .idle}
            if !items.isEmpty {progress="Settings changed. Preview again."}
        }
        if componentWorkflow {
            rows=rows.map {row in var value=row;if value.planned != nil {value.status="Preview outdated";value.issue="Preview the changed tab before applying."};return value}
            let ticket=revision
            Task {[weak self] in await self?.recomposeComponents(ticket:ticket)}
            return
        }
        rows=rows.filter {row in row.item.map {item in row.id==item.snapshot.id.physicalKey} ?? true}.map {row in
            var value=row;value.planned=nil;value.groupID=nil
            if ["eligible","blocked"].contains(value.status) {value.status="imported";value.issue=nil}
            return value
        }
    }
    func importURLs(_ urls:[URL]) async {
        guard ![.running,.cancelling,.recovering].contains(phase) else {return}
        cancelWork?();componentPlans=[:];componentWorkflow=false;invalidatePreview();issue=nil
        importedURLs=Array(Set(importedURLs+urls.map(\.standardizedFileURL))).sorted {$0.path<$1.path}
        options.importRoots=importedURLs
        let ticket=revision;phase = .importing;progress="Reading file metadata…"
        let backend=self.backend,roots=importedURLs
        var scope=discovery
        scope.excludedRoots+=[options.mode == .saveCopies ? options.outputRoot:nil,options.recoveryRoot].compactMap {$0}
        let task=Task {[weak self] in try await backend.inspectDetailed(roots,options:scope,progress:{[weak self] value in await self?.receivePreparation(value,ticket:ticket)})};cancelWork={task.cancel()}
        do {
            let result=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            guard ticket==revision,!task.isCancelled else {return}
            items=result.items
            rows=result.items.map {.init(id:$0.snapshot.id.physicalKey,url:$0.snapshot.url,item:$0,status:"imported")}
            rows+=result.excluded.map {.init(id:"excluded:"+$0.url.standardizedFileURL.path,url:$0.url,item:nil,status:"excluded",issue:$0.reason)}
            phase = .idle;progress="\(result.items.count) items imported; \(result.excluded.count) excluded"
        } catch {if ticket==revision {phase = task.isCancelled ? .idle:.failed;issue=task.isCancelled ? nil:error.localizedDescription;progress=task.isCancelled ? "Import cancelled.":"Import needs attention."}}
        if ticket==revision {cancelWork=nil;preparationProgress=nil}
    }
    func preview(component:PreviewComponent) async {
        guard !isBusy else {return}
        guard !items.isEmpty else {issue="Add files or a folder first.";return}
        compositionGeneration+=1;componentWorkflow=true;plan=nil;previewRevision=nil;issue=nil;blockedReasons=[];preparationProgress=nil;phase = .planning
        progress="Previewing "+component.title+"…"
        let ticket=revision,backend=self.backend,inputs=items,scoped=component.request(from:request),options=self.options
        let task=Task {[weak self] in try await backend.preview(items:inputs,request:scoped,options:options,progress:{[weak self] value in await self?.receivePreparation(value,ticket:ticket)})}
        cancelWork={task.cancel()}
        do {
            let value=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            guard ticket==revision,!task.isCancelled else {return}
            componentPlans[component]=value
            await recomposeComponents(ticket:ticket,last:component)
        } catch {if ticket==revision {phase = task.isCancelled ? .idle:.failed;issue=task.isCancelled ? nil:error.localizedDescription;progress=task.isCancelled ? "Preview cancelled.":"Preview needs attention."}}
        if ticket==revision {cancelWork=nil;preparationProgress=nil}
    }
    private func cachedRequest()->OperationRequest {
        var value=OperationRequest();value.groups=request.groups;value.excludedSourceKeys=request.excludedSourceKeys
        if PreviewComponent.dates.isSelected(in:request),let part=componentPlans[.dates]?.request {value.dates=part.dates;value.metadataDestination=part.metadataDestination}
        if PreviewComponent.places.isSelected(in:request),let part=componentPlans[.places]?.request {value.location=part.location;value.rename=part.rename;value.placeQuery=part.placeQuery;value.placeOverrides=part.placeOverrides;value.metadataDestination=part.metadataDestination}
        if PreviewComponent.metadata.isSelected(in:request),let part=componentPlans[.metadata]?.request {value.tags=part.tags;value.removeGPS=part.removeGPS;value.stripMetadata=part.stripMetadata;value.metadataDestination=part.metadataDestination}
        if PreviewComponent.finder.isSelected(in:request),let part=componentPlans[.finder]?.request {value.finder=part.finder}
        return value
    }
    private func recomposeComponents(ticket:Int,last:PreviewComponent?=nil) async {
        guard componentWorkflow,ticket==revision,!componentPlans.isEmpty else {return}
        guard !isBusy || (last != nil && phase == .planning) else {return}
        compositionGeneration+=1
        let generation=compositionGeneration
        let components=componentPlans,displayRequest=cachedRequest(),options=self.options,currentRequest=request
        do {
            let display:BatchPlan
            if PreviewComponent.allCases.contains(where:{$0.isSelected(in:displayRequest)}) {
                display=try await Task.detached {try await BatchPlanComposer().combine(components:components,request:displayRequest,options:options)}.value
            } else {display=components[last ?? activePreviewComponent] ?? components.values.first!}
            guard ticket==revision,generation==compositionGeneration else {return}
            show(display)
            let missing=pendingPreviewComponents
            if missing.isEmpty,PreviewComponent.allCases.contains(where:{$0.isSelected(in:currentRequest)}) {
                let combined=try await Task.detached {try await BatchPlanComposer().combine(components:components,request:currentRequest,options:options)}.value
                guard ticket==revision,generation==compositionGeneration else {return}
                plan=combined;previewRevision=ticket;show(combined);phase = .ready;summarize(combined)
            } else {
                plan=nil;previewRevision=nil;phase = .idle;blockedReasons=[]
                let stale=missing.contains {components[$0] != nil}
                if stale {rows=rows.map {row in var value=row;value.status="Preview outdated";return value}}
                progress=missing.isEmpty ? "No changes selected.":"Preview ready. Also preview: "+missing.map(\.title).joined(separator:", ")+"."
            }
        } catch {if ticket==revision,generation==compositionGeneration {plan=nil;previewRevision=nil;phase = .idle;issue=error.localizedDescription;progress="Review the selected previews."}}
    }
    private func summarize(_ value:BatchPlan) {
        var counts=[String:Int]()
        for group in value.groups where group.eligibility == .blocked {for reason in Set(group.blockingReasons) {counts[reason,default:0]+=1}}
        blockedReasons=counts.map {BlockingReasonSummary(reason:$0.key,groupCount:$0.value)}.sorted {$0.groupCount==$1.groupCount ? $0.reason<$1.reason:$0.groupCount>$1.groupCount}
        progress="\(value.eligibleGroups.count) eligible asset groups; \(value.groups.filter {$0.eligibility == .blocked}.count) blocked"
        if value.destinationPending {progress+=" • Choose the output folder when applying."}
    }
    func preview() async {
        guard !isBusy else {return}
        guard !items.isEmpty else {issue="Add files or a folder first.";return}
        plan=nil;previewRevision=nil;issue=nil;blockedReasons=[];preparationProgress=nil;phase = .planning;progress="Building a preview…"
        let ticket=revision,backend=self.backend,inputs=items,request=self.request,options=self.options
        let task=Task {[weak self] in try await backend.preview(items:inputs,request:request,options:options,progress:{[weak self] value in await self?.receivePreparation(value,ticket:ticket)})};cancelWork={task.cancel()}
        do {
            let value=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            guard ticket==revision,!task.isCancelled else {return}
            plan=value;previewRevision=ticket;show(value);phase = .ready
            var counts=[String:Int]()
            for group in value.groups where group.eligibility == .blocked {
                for reason in Set(group.blockingReasons) {counts[reason,default:0]+=1}
            }
            blockedReasons=counts.map {BlockingReasonSummary(reason:$0.key,groupCount:$0.value)}.sorted {a,b in a.groupCount==b.groupCount ? a.reason<b.reason:a.groupCount>b.groupCount}
            progress="\(value.eligibleGroups.count) eligible asset groups; \(value.groups.filter {$0.eligibility == .blocked}.count) blocked"
        } catch {if ticket==revision {phase = task.isCancelled ? .idle:.failed;issue=task.isCancelled ? nil:error.localizedDescription;progress=task.isCancelled ? "Preview cancelled.":"Preview needs attention."}}
        if ticket==revision {cancelWork=nil;preparationProgress=nil}
    }
    private func receivePreparation(_ value:PreparationProgress,ticket:Int) {
        guard ticket==revision,phase == .importing || phase == .planning else {return}
        let now=DispatchTime.now().uptimeNanoseconds
        guard preparationProgress?.stage != value.stage || value.completed==value.total || now-lastPreparationPublication>=100_000_000 else {return}
        preparationProgress=value;progress=value.message;lastPreparationPublication=now
    }
    private func show(_ plan:BatchPlan) {
        let known=Dictionary(uniqueKeysWithValues:items.map {($0.snapshot.id.physicalKey,$0)})
        let excluded=rows.filter {$0.item==nil}
        let placePlan=componentPlans[.places]
        let lookupItems=placePlan?.request == PreviewComponent.places.request(from:request) ? Dictionary(uniqueKeysWithValues:(placePlan?.groups.flatMap(\.items) ?? []).map {($0.name.sourceKey,$0)}):[:]
        rows=plan.groups.flatMap {group in group.items.map {item in
            let lookup=lookupItems[item.name.sourceKey]
            let projected=PlannedItem(source:item.source,metadata:item.metadata,resolution:item.resolution,place:item.place ?? lookup?.place,placeCandidates:item.placeCandidates ?? lookup?.placeCandidates,name:item.name,mutation:item.mutation,capabilities:item.capabilities,destinationAnchor:item.destinationAnchor,blockingReasons:item.blockingReasons)
            return MediaRow(id:item.name.sourceKey,url:item.source.snapshot.url,item:known[item.source.snapshot.id.physicalKey],planned:projected,groupID:group.id,status:group.eligibility.rawValue,issue:group.blockingReasons.isEmpty ? nil:group.blockingReasons.joined(separator:"\n"))
        }}
        rows+=excluded
    }
    func applyPreview(outputFolder:URL?=nil) async {
        guard canApply,let initial=plan else {return}
        if initial.destinationPending {
            guard let folder=outputFolder else {issue="Choose the Save Copies folder when applying changes.";return}
            do {
                let ticket=revision
                let bound=try await Task.detached {try await BatchPlanComposer().bindDestination(initial,to:folder)}.value
                guard ticket==revision else {return}
                options.outputRoot=folder;plan=bound;previewRevision=revision;phase = .ready;show(bound);summarize(bound)
                let originalReasons=Set(initial.groups.flatMap(\.blockingReasons))
                if !Set(bound.groups.flatMap(\.blockingReasons)).subtracting(originalReasons).isEmpty {issue="Destination conflicts found. Review the preview before applying.";return}
            } catch {issue=error.localizedDescription;return}
        }
        guard canApply,let frozen=plan else {return}
        compositionGeneration+=1;activePlan=frozen;plan=nil;previewRevision=nil;phase = .running;issue=nil;progress="Starting batch…"
        blockedReasons=[];preparationProgress=nil
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
        componentPlans=[:];compositionGeneration+=1
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
            cancelWork?();revision+=1;compositionGeneration+=1;plan=nil;previewRevision=nil;phase = .idle;progress="Cancelled."
            preparationProgress=nil;blockedReasons=[]
        }
    }
    func restore(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?=nil) async {
        guard !isBusy else {return};phase = .recovering;issue=nil;progress="Restoring verified originals…"
        do {
            await backend.setRecoveryRoot(options.recoveryRoot)
            let result=try await backend.restore(batchID:batchID,choice:choice,selectedSourceKeys:selectedSourceKeys)
            if !result.isComplete {issue=result.conflicts.joined(separator:"\n")}
            progress=result.isComplete ? "Recovery completed.":"Recovery has conflicts to review."
        } catch {issue=error.localizedDescription;progress="Recovery stopped; retained originals remain available."}
        phase = .finished
    }
    func clear() {guard !isBusy else {return};componentPlans=[:];componentWorkflow=false;invalidatePreview();items=[];importedURLs=[];rows=[];report=nil;issue=nil;progress=""}
    func presentError(_ error:Error) {issue=error.localizedDescription}
}
