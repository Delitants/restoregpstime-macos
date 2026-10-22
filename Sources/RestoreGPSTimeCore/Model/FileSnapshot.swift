import Foundation

public typealias ContentHash = String
public enum FileKind: String, Codable, Sendable { case regular, directory, symlink, package, unavailable }
public struct SourceID: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: UInt64
    public let modified: Date
    public let changed: Date
    public let linkCount: UInt64
    public let volumeID: String
    public var physicalKey: String { "\(device):\(inode)" }
}
public struct FileSnapshot: Codable, Equatable, Sendable {
    public let url: URL
    public let id: SourceID
    public let kind: FileKind
    public let creationDate: Date
    public let modificationDate: Date
    public let flags: UInt32
    public let permissions: UInt16
    public let ownerID:UInt32,groupID:UInt32
    public let xattrHashes: [String:ContentHash]
    public let finderInfo: Data?
    public let aclText: String?
    public var isLocked: Bool { flags & 0x2 != 0 }
}
public struct SourceFingerprint: Codable, Equatable, Sendable {
    public let snapshot: FileSnapshot
    public let contentHash: ContentHash
}
