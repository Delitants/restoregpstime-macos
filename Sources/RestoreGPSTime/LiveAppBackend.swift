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
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem] {try await inspectDetailed(urls,options:options).items}
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection {
        let inventory=await SourceInventory().scan(urls:urls,options:options),reader=self.reader
        try Task.checkCancellation()
        let items=try await withThrowingTaskGroup(of:InspectedItem.self,returning:[InspectedItem].self) {group in
            for snapshot in inventory.snapshots {group.addTask {
                try Task.checkCancellation()
                do {return .init(snapshot:snapshot,metadata:try await reader.read(snapshot:snapshot))}
                catch {try Task.checkCancellation();return .init(snapshot:snapshot,metadata:.init(tags:[:],diagnostics:[error.localizedDescription]))}
            }}
            var values=[InspectedItem]();for try await value in group {values.append(value)}
            return values.sorted {$0.snapshot.url.path<$1.snapshot.url.path}
        }
        return .init(items:items,excluded:inventory.excluded)
    }
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {
        var resolved=items
        if request.location != nil || !request.rename.preserveOriginal {
            for index in resolved.indices {
                try Task.checkCancellation()
                let key=resolved[index].snapshot.id.physicalKey
                if let manual=request.placeOverrides[key] {resolved[index].place=manual}
                else {resolved[index].place=try? await places.resolve(document:resolved[index].metadata,correction:nil).first}
            }
        }
        let identity=try await provider.observe()
        return try await BatchPlanner(dependencies:identity,reader:reader).preview(items:resolved,request:request,options:options)
    }
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent> {lastRecoveryRoot=plan.options.recoveryRoot;return executor.execute(plan)}
    func cancel(_ id:UUID) async {await executor.cancel(batchID:id)}
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {
        guard let root=lastRecoveryRoot else {throw RestoreError(.missingMetadata,"Choose the recovery folder first.")}
        return try await RecoveryCoordinator(root:root,driver:AttributeMutationDriver(paths:paths)).restore(batchID:batchID,choice:choice)
    }
    private var lastRecoveryRoot:URL?
    func setRecoveryRoot(_ root:URL?) {lastRecoveryRoot=root}
}
