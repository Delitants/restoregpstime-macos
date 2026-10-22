import Foundation

public struct CapabilityRegistry {
    private let profiles:[String:[String:Bool]]
    public init() {
        let shipped=Bundle.main.url(forResource:"container-capabilities",withExtension:"json")
        let local=Bundle.main.bundleURL.pathExtension=="app" ? nil : Bundle.module.url(forResource:"container-capabilities",withExtension:"json")
        if let url=shipped ?? local, let data=try? Data(contentsOf:url),let policy=try? JSONDecoder().decode(Policy.self,from:data),policy.schema==1 { profiles=policy.profiles }
        else { profiles=[:] }
    }
    public func decision(for operation: OperationKind, document: MetadataDocument, snapshot: FileSnapshot) -> CapabilityDecision {
        guard snapshot.kind == .regular || snapshot.kind == .directory else { return .init(false,"This item is unavailable, linked, or a package.") }
        switch operation {
        case .filesystemDates,.rename,.finderAttributes: return .init(true)
        case .embeddedWrite,.removeGPS,.stripMetadata:
            if profiles[document.profile.identifier]?[operation.rawValue]==true { return .init(true) }
            return .init(false,"Embedded writes for \(document.profile.identifier) require a verified tag and media-integrity profile.")
        }
    }
}

private struct Policy:Decodable { let schema:Int;let profiles:[String:[String:Bool]] }
