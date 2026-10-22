import Foundation

public struct NameReservation:Codable,Equatable,Sendable {
    public let groupID:UUID,sourceKey:String,originalURL:URL,finalURL:URL
    public let sequence:Int?
    public let wasTruncated:Bool
    public let needsTemporaryRename:Bool
    public let blockingReason:String?
}
public struct DestinationContext:Sendable {
    public let root:URL?
    public let saveCopies:Bool
    public let importRoots:[URL]
    public let rules:VolumeNamingRules
    public init(root:URL?=nil,saveCopies:Bool,importRoots:[URL]=[],rules:VolumeNamingRules=VolumeNamingRules()) { self.root=root;self.saveCopies=saveCopies;self.importRoots=importRoots;self.rules=rules }
}
