import Foundation

public enum PlanEligibility:String,Codable,Sendable {case eligible,blocked,excluded}
public struct DependencyIdentity:Codable,Equatable,Sendable {
    public let engineHash:String,databaseHash:String,capabilityHash:String
    public init(engineHash:String,databaseHash:String,capabilityHash:String) {self.engineHash=engineHash;self.databaseHash=databaseHash;self.capabilityHash=capabilityHash}
}
public struct DestinationAnchor:Codable,Equatable,Sendable {
    public let requestedURL:URL,resolvedURL:URL,identity:SourceID
}
public struct PlannedItem:Codable,Equatable,Sendable {
    public let source:SourceFingerprint
    public let metadata:MetadataDocument
    public let resolution:DateResolution?
    public let place:PlaceMatch?
    public let name:NameReservation
    public let mutation:MutationPlan
    public let capabilities:[String:CapabilityDecision]
    public let destinationAnchor:DestinationAnchor?
    public let blockingReasons:[String]
}
public struct PlannedGroup:Codable,Equatable,Sendable {
    public let id:UUID
    public let evidence:String
    public let items:[PlannedItem]
    public let eligibility:PlanEligibility
    public let blockingReasons:[String]
}
public struct BatchPlan:Codable,Equatable,Sendable {
    public let schema:Int
    public let id:UUID
    public let optionsDigest:String
    public let frozenNow:Date
    public let dependencies:DependencyIdentity
    public let request:OperationRequest
    public let options:BatchOptions
    public let groups:[PlannedGroup]
    public var eligibleGroups:[PlannedGroup] {groups.filter {$0.eligibility == .eligible}}
    public init(id:UUID=UUID(),optionsDigest:String,frozenNow:Date,dependencies:DependencyIdentity,request:OperationRequest,options:BatchOptions,groups:[PlannedGroup]) {
        schema=1;self.id=id;self.optionsDigest=optionsDigest;self.frozenNow=frozenNow;self.dependencies=dependencies;self.request=request;self.options=options;self.groups=groups
    }
}
public struct PlanConflict:Codable,Equatable,Sendable {public let groupID:UUID?;public let sourceKey:String?;public let error:RestoreError}
public struct PlanValidationResult:Codable,Equatable,Sendable {
    public let conflicts:[PlanConflict]
    public var isValid:Bool {conflicts.isEmpty}
}
