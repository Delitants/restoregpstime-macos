import Foundation

public enum PlannedOutputKind:String,Codable,Sendable {case sourceCopy,xmpSidecar}
public struct MutationPlan:Codable,Equatable,Sendable {
    public let dates:DateMutation?
    public let tags:[TagMutation]
    public let removeGPS:Bool,stripMetadata:Bool
    public let finder:[FinderMutation]
    public let outputKind:PlannedOutputKind
    public let profile:ContainerProfile
    public let allowedMetadataChanges:AllowedMetadataChanges
    public var changesContent:Bool {outputKind == .xmpSidecar || !tags.isEmpty || removeGPS || stripMetadata || dates?.embeddedDate != nil || dates?.removeEmbeddedDates == true}
    public var explicitlyUnlocks:Bool {finder.contains(.locked(false))}
    public var isFinderNotificationOnly:Bool {dates==nil && tags.isEmpty && !removeGPS && !stripMetadata && outputKind == .sourceCopy && !finder.isEmpty && finder.allSatisfy {$0 == .notify}}
    public init(dates:DateMutation?=nil,tags:[TagMutation]=[],removeGPS:Bool=false,stripMetadata:Bool=false,finder:[FinderMutation]=[],outputKind:PlannedOutputKind = .sourceCopy,profile:ContainerProfile = .init(identifier:"UNKNOWN",family:.unknown),allowedMetadataChanges:AllowedMetadataChanges=AllowedMetadataChanges()) {
        self.dates=dates;self.tags=tags;self.removeGPS=removeGPS;self.stripMetadata=stripMetadata;self.finder=finder;self.outputKind=outputKind;self.profile=profile;self.allowedMetadataChanges=allowedMetadataChanges
    }
}
