import Foundation
import Darwin

public struct PlanValidator:Sendable {
    let dependencies:@Sendable () async throws -> DependencyIdentity
    public init(dependencies:@escaping @Sendable () async throws -> DependencyIdentity) {self.dependencies=dependencies}
    public func revalidate(_ plan:BatchPlan) async -> PlanValidationResult {
        let worker=Task.detached(priority:.userInitiated) {await validateBlocking(plan)}
        return await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
    }
    private func validateBlocking(_ plan:BatchPlan) async -> PlanValidationResult {
        var conflicts=[PlanConflict]()
        func conflict(_ message:String,group:UUID?=nil,source:String?=nil) {conflicts.append(.init(groupID:group,sourceKey:source,error:.init(.conflict,message)))}
        guard plan.schema==1 else {conflict("Unsupported batch plan schema.");return .init(conflicts:conflicts)}
        do {
            if try BatchPlanner.settingsDigest(request:plan.request,options:plan.options) != plan.optionsDigest {conflict("The plan's operation settings changed. Preview again.")}
            if try await dependencies() != plan.dependencies {conflict("The metadata runtime, location database or write capabilities changed. Preview again.")}
        } catch {conflict(error.localizedDescription)}
        let reader=FileIdentityReader();var checked=Set<String>(),destinations=Set<String>()
        for group in plan.eligibleGroups {
            for item in group.items {
                if Task.isCancelled {conflicts.append(.init(groupID:group.id,sourceKey:item.name.sourceKey,error:.init(.cancelled,"Validation cancelled.")));return .init(conflicts:conflicts)}
                let source=item.source.snapshot
                if checked.insert(source.id.physicalKey).inserted {
                    do {if try reader.fingerprint(at:source.url) != item.source {conflict("The source content or attributes changed after preview.",group:group.id,source:item.name.sourceKey)}}
                    catch {conflict(error.localizedDescription,group:group.id,source:item.name.sourceKey)}
                }
                do {
                    guard let anchor=item.destinationAnchor else {throw RestoreError(.conflict,"Missing destination identity.")}
                    let current=try reader.snapshot(at:anchor.requestedURL)
                    guard current.kind == .directory,current.id.physicalKey==anchor.identity.physicalKey,current.id.volumeID==anchor.identity.volumeID,(try FileSystemPath.canonicalDirectory(anchor.requestedURL)).path==anchor.resolvedURL.path else {throw RestoreError(.conflict,"The destination parent or volume changed.")}
                    let parent=item.name.finalURL.deletingLastPathComponent()
                    let rules=try VolumeNamingRules.detect(at:anchor.requestedURL),key=rules.collisionKey(item.name.finalURL.path)
                    guard destinations.insert(key).inserted else {throw RestoreError(.conflict,"Two items reserve the same destination.")}
                    var cursor=parent,st=stat()
                    while cursor.path != anchor.requestedURL.path && BatchPlanner.isWithin(cursor,anchor.requestedURL) {
                        if lstat(cursor.path,&st)==0 && st.st_mode & S_IFMT != S_IFDIR {throw RestoreError(.conflict,"A new destination parent is not an ordinary directory.")}
                        cursor=cursor.deletingLastPathComponent()
                    }
                    if lstat(parent.path,&st)==0 {
                        for entry in try FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil) where rules.collisionKey(entry.lastPathComponent)==rules.collisionKey(item.name.finalURL.lastPathComponent) {
                            let own=plan.options.mode == .modifyInPlace && item.mutation.outputKind == .sourceCopy && entry.standardizedFileURL.path==source.url.standardizedFileURL.path
                            if !own {throw RestoreError(.conflict,"A destination was occupied after preview.")}
                        }
                    } else if errno != ENOENT {throw RestoreError(.io,"Cannot recheck the destination parent.")}
                } catch {conflict(error.localizedDescription,group:group.id,source:item.name.sourceKey)}
            }
        }
        return .init(conflicts:conflicts)
    }
}
