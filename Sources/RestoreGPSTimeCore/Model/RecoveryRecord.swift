import Foundation

public enum RecoveryPhase:String,Codable,CaseIterable,Sendable {case prepared,backedUp,staged,verified,committing,committed,failed,cancelled,recoveryNeeded,restoring,restored}
public enum CommitStep:String,Codable,Sendable {case pending,unlockPending,unlocked,swapPending,swapped,publishPending,published,retirePending,retired,flagsPending,complete,directoryPending}
public struct RecoveryMember:Codable,Equatable,Sendable {
    public let item:PlannedItem
    public var compactHash:String?
    public var backupURL:URL?
    public var backupHash:String?
    public var stageURL:URL?
    public var staged:SourceFingerprint?
    public var heldOriginalURL:URL?
    public var step:CommitStep = .pending
    public var after:SourceFingerprint?
    public var restoreStageURL:URL?
    public var restoreFingerprint:SourceFingerprint?
    public var recoveryRetiredURL:URL?
    public var recoveryRetiredFingerprint:SourceFingerprint?
    public var restored:Bool=false
    public init(item:PlannedItem) {self.item=item}
}
public struct RecoveryRecord:Codable,Equatable,Sendable {
    public let schema:Int
    public let batchID:UUID,groupID:UUID
    public let options:BatchOptions
    public let createdAt:Date
    /// Present only after the whole group commit is durable. Cleanup is retryable.
    public var compactCleanup:Bool?
    public var phase:RecoveryPhase
    public var members:[RecoveryMember]
    public var stageDirectories=[URL]()
    public var directoryIntents=[URL]()
    public var createdDirectories=[String:SourceID]()
    public var errors=[String]()
    public init(batchID:UUID,group:PlannedGroup,options:BatchOptions) {schema=1;self.batchID=batchID;groupID=group.id;self.options=options;createdAt=Date();phase = .prepared;members=group.items.map {RecoveryMember(item:$0)}}
}
public enum RecoveryChoice:Sendable {case originalLocations,separateFolder(URL)}
public struct RecoveryOutcome:Sendable {
    public let batchID:UUID
    public let restored:[URL]
    public let conflicts:[String]
    public var isComplete:Bool {conflicts.isEmpty}
}
