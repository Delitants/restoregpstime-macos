import Foundation
import RestoreGPSTimeCore

actor LiveAppBackend:AppBackend {
    let paths:RuntimePaths
    private let provider:DependencyIdentityProvider,reader:MetadataReader,places:OfflinePlaceResolver,executor:BatchExecutor
    init(paths:RuntimePaths) {
        self.paths=paths
        let provider=DependencyIdentityProvider(paths:paths)
        self.provider=provider;reader=MetadataReader(paths:paths);places=OfflinePlaceResolver(paths:paths)
        executor=BatchExecutor(driver:AttributeMutationDriver(paths:paths),validator:.init(dependencies:{try await provider.observe()}))
    }
    private var previewFingerprints=[String:SourceFingerprint]()
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem] {try await inspectDetailed(urls,options:options).items}
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection {
        try await inspectDetailed(urls,options:options,progress:{_ in})
    }
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> AppInspection {
        await progress(.init(stage:.discovering))
        let inventory=await SourceInventory().scan(urls:urls,options:options),reader=self.reader
        try Task.checkCancellation()
        await progress(.init(stage:.metadata,total:inventory.snapshots.count))
        let chunks=stride(from:0,to:inventory.snapshots.count,by:32).map {Array(inventory.snapshots[$0..<min($0+32,inventory.snapshots.count)])}
        let items=try await withThrowingTaskGroup(of:[InspectedItem].self,returning:[InspectedItem].self) {group in
            var next=0,values=[InspectedItem]()
            func enqueue(_ chunk:[FileSnapshot]) {
                group.addTask {
                    try Task.checkCancellation()
                    do {return try await zip(chunk,reader.readBatch(snapshots:chunk)).map {.init(snapshot:$0.0,metadata:$0.1)}}
                    catch {
                        // Isolate helper/JSON failures to individual files; keep good files usable.
                        try Task.checkCancellation()
                        var recovered=[InspectedItem]()
                        for snapshot in chunk {
                            try Task.checkCancellation()
                            do {recovered.append(.init(snapshot:snapshot,metadata:try await reader.read(snapshot:snapshot)))}
                            catch {try Task.checkCancellation();recovered.append(.init(snapshot:snapshot,metadata:.init(tags:[:],diagnostics:[error.localizedDescription])))}
                        }
                        return recovered
                    }
                }
            }
            while next<min(2,chunks.count) {enqueue(chunks[next]);next+=1}
            while let completed=try await group.next() {
                values+=completed
                await progress(.init(stage:.metadata,completed:values.count,total:inventory.snapshots.count))
                if next<chunks.count {enqueue(chunks[next]);next+=1}
            }
            return values.sorted {$0.snapshot.url.path<$1.snapshot.url.path}
        }
        let keys=Set(items.map {$0.snapshot.id.physicalKey});previewFingerprints=previewFingerprints.filter {keys.contains($0.key)}
        return .init(items:items,excluded:inventory.excluded)
    }
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {
        try await preview(items:items,request:request,options:options,progress:{_ in})
    }
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions,progress:@escaping @Sendable (PreparationProgress) async -> Void) async throws -> BatchPlan {
        var resolved=items
        if request.location != nil || !request.rename.preserveOriginal || request.placeQuery != nil {
            await progress(.init(stage:.places,total:items.count))
            for index in resolved.indices {
                try Task.checkCancellation()
                let key=resolved[index].snapshot.id.physicalKey
                if let manual=request.placeOverrides[key] {resolved[index].place=manual}
                else {
                    let candidates=try? await places.resolve(document:resolved[index].metadata,correction:nil,queryDefaults:request.placeQuery ?? PlaceQueryDefaults())
                    resolved[index].placeCandidates=candidates
                    resolved[index].place=candidates?.first
                }
                await progress(.init(stage:.places,completed:index+1,total:items.count))
            }
        }
        try Task.checkCancellation()
        await progress(.init(stage:.dependencies))
        let identity=try await provider.observe()
        let plan=try await BatchPlanner(dependencies:identity,reader:reader).preview(items:resolved,request:request,options:options,allowUnresolvedDestination:true,cachedFingerprints:previewFingerprints,progress:progress)
        for item in plan.groups.flatMap(\.items) {previewFingerprints[item.source.snapshot.id.physicalKey]=item.source}
        return plan
    }
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent> {lastRecoveryRoot=plan.options.recoveryRoot;return executor.execute(plan)}
    func cancel(_ id:UUID) async {await executor.cancel(batchID:id)}
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {try await restore(batchID:batchID,choice:choice,selectedSourceKeys:nil)}
    func restore(batchID:UUID,choice:RecoveryChoice,selectedSourceKeys:Set<String>?) async throws -> RecoveryOutcome {
        guard let root=lastRecoveryRoot else {throw RestoreError(.missingMetadata,"Choose the recovery folder first.")}
        return try await RecoveryCoordinator(root:root,driver:AttributeMutationDriver(paths:paths)).restore(batchID:batchID,choice:choice,selectedSourceKeys:selectedSourceKeys)
    }
    private var lastRecoveryRoot:URL?
    func setRecoveryRoot(_ root:URL?) {lastRecoveryRoot=root}
}
