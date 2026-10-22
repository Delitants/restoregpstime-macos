import Foundation

public struct AllowedMetadataChanges:Codable,Equatable,Sendable {
    public let tags:Set<String>
    public let removesGPS:Bool,stripsDescriptive:Bool
    public init(tags:Set<String>=[],removesGPS:Bool=false,stripsDescriptive:Bool=false) {self.tags=tags;self.removesGPS=removesGPS;self.stripsDescriptive=stripsDescriptive}
}
public struct StageVerification:Codable,Equatable,Sendable {
    public let contentHash:String
    public let integrityValidator:String
    public let verifiedTags:[String:TagValue]
    public let notes:[String]
    public init(contentHash:String,integrityValidator:String,verifiedTags:[String:TagValue]=[:],notes:[String]=[]) {self.contentHash=contentHash;self.integrityValidator=integrityValidator;self.verifiedTags=verifiedTags;self.notes=notes}
}
public protocol MutationDriver:Sendable {
    func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification
    func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws
}
