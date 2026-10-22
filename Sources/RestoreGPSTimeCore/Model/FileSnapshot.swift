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
    public let modifiedTimestamp:FileTimestamp?,changedTimestamp:FileTimestamp?
    init(device:UInt64,inode:UInt64,size:UInt64,modified:Date,changed:Date,linkCount:UInt64,volumeID:String,modifiedTimestamp:FileTimestamp?=nil,changedTimestamp:FileTimestamp?=nil) {
        self.device=device;self.inode=inode;self.size=size;self.modified=modified;self.changed=changed;self.linkCount=linkCount;self.volumeID=volumeID;self.modifiedTimestamp=modifiedTimestamp;self.changedTimestamp=changedTimestamp
    }
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
    public let creationTimestamp:FileTimestamp?,modificationTimestamp:FileTimestamp?
    init(url:URL,id:SourceID,kind:FileKind,creationDate:Date,modificationDate:Date,flags:UInt32,permissions:UInt16,ownerID:UInt32,groupID:UInt32,xattrHashes:[String:ContentHash],finderInfo:Data?,aclText:String?,creationTimestamp:FileTimestamp?=nil,modificationTimestamp:FileTimestamp?=nil) {
        self.url=url;self.id=id;self.kind=kind;self.creationDate=creationDate;self.modificationDate=modificationDate;self.flags=flags;self.permissions=permissions;self.ownerID=ownerID;self.groupID=groupID;self.xattrHashes=xattrHashes;self.finderInfo=finderInfo;self.aclText=aclText;self.creationTimestamp=creationTimestamp;self.modificationTimestamp=modificationTimestamp
    }
    public var isLocked: Bool { flags & 0x2 != 0 }
}
public struct SourceFingerprint: Codable, Equatable, Sendable {
    public let snapshot: FileSnapshot
    public let contentHash: ContentHash
}
