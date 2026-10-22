import Foundation

public struct AssetGroup:Codable,Equatable,Sendable {
    public let id:UUID
    public let members:[InspectedItem]
    public let evidence:String
    public var primary:InspectedItem { members.first(where:{$0.metadata.profile.family == .photo || $0.metadata.profile.family == .raw}) ?? members[0] }
    public init(members:[InspectedItem],evidence:String="Independent file") throws {
        guard !members.isEmpty else { throw RestoreError(.invalidInput,"An asset group cannot be empty.") }
        self.members=members;self.evidence=evidence
        let hash=FileIdentityReader.hash(Data(members.map {$0.snapshot.id.physicalKey}.sorted().joined(separator:"|").utf8))
        let n=Array(hash.prefix(32));let uuid="\(String(n[0..<8]))-\(String(n[8..<12]))-\(String(n[12..<16]))-\(String(n[16..<20]))-\(String(n[20..<32]))"
        id=UUID(uuidString:uuid)!
    }
}
public struct GroupOverrides:Codable,Equatable,Sendable {
    public var unlinkedSourceKeys=Set<String>()
    public var forcedGroups=[[String]]()
    public init() {}
}
