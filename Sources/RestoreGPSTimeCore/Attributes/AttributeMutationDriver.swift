import Foundation

public actor AttributeMutationDriver:MutationDriver {
    let metadata:MetadataMutationDriver
    public init(paths:RuntimePaths) {metadata=MetadataMutationDriver(paths:paths)}
    public func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification {
        try StageOwnership.shared.require(stage)
        let result=try await metadata.apply(mutation,to:stage)
        let finder=mutation.finder.filter {switch $0 {case .locked,.notify:return false;default:return true}}
        if !finder.isEmpty {_ = try FinderAttributeWriter().apply(.init(mutations:finder),to:stage)}
        if let dates=mutation.dates {_ = try FileDateWriter().apply(.init(creationDate:dates.creationDate,modificationDate:dates.modificationDate),to:stage)}
        let final=try FileIdentityReader().fingerprint(at:stage)
        guard final.contentHash==result.contentHash else {throw RestoreError(.verificationFailed,"An attribute write changed the verified media bytes.")}
        return .init(contentHash:final.contentHash,integrityValidator:result.integrityValidator,verifiedTags:result.verifiedTags,notes:result.notes+["Selected Finder attributes and final filesystem dates verified; final lock is applied at commit."])
    }
    public func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws {try await metadata.restoreAttributes(snapshot,to:stage)}
}
