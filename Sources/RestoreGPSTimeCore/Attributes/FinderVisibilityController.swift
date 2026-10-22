import Foundation
import Darwin

public enum FinderPreferenceValue:Codable,Equatable,Sendable {case absent,bool(Bool),string(String),integer(Int)}
public protocol FinderVisibilityBackend:Sendable {
    func read() throws -> FinderPreferenceValue
    func write(_ value:FinderPreferenceValue) throws
    func restart() async -> Bool
}
public struct FinderVisibilityChange:Codable,Equatable,Sendable {
    public let id:UUID,previous:FinderPreferenceValue,visible:Bool
}
public struct FinderVisibilityResult:Sendable {public let restarted:Bool,requiresRestart:Bool,note:String}
public actor FinderVisibilityController {
    private let backend:any FinderVisibilityBackend
    private let recordURL:URL?
    private var retained:SavedVisibilityChange?
    private var busy=false
    public init(backend:any FinderVisibilityBackend,recordURL:URL?=nil) {self.backend=backend;self.recordURL=recordURL}
    public func preview(visible:Bool) throws -> FinderVisibilityChange {.init(id:UUID(),previous:try backend.read(),visible:visible)}
    public func apply(_ change:FinderVisibilityChange,restartApproved:Bool) async throws -> FinderVisibilityResult {
        guard !busy else {throw RestoreError(.conflict,"A Finder visibility operation is already running.")}
        busy=true;defer {busy=false}
        guard try backend.read()==change.previous else {throw RestoreError(.conflict,"The Finder preference changed after preview. Review it again.")}
        var record=SavedVisibilityChange(schema:1,change:change,phase:.prepared)
        try persist(record) // Retain the previous value before changing the system preference.
        try backend.write(.bool(change.visible))
        guard try backend.read() == .bool(change.visible) else {throw RestoreError(.verificationFailed,"The Finder preference did not read back as requested.")}
        record.phase = .applied;try persist(record)
        return await finish(restartApproved:restartApproved,note:"Finder visibility preference saved.")
    }
    public func restorePrevious(restartApproved:Bool) async throws -> FinderVisibilityResult {
        guard !busy else {throw RestoreError(.conflict,"A Finder visibility operation is already running.")}
        busy=true;defer {busy=false}
        guard var record=try load() else {throw RestoreError(.missingMetadata,"No previous Finder visibility preference was retained.")}
        let current=try backend.read(),expected=FinderPreferenceValue.bool(record.change.visible)
        if record.phase == .restored {
            guard current==record.change.previous else {throw RestoreError(.conflict,"The Finder preference changed after restoration.")}
        } else {
            guard current==expected || (record.phase == .prepared && current==record.change.previous) else {throw RestoreError(.conflict,"The Finder preference changed externally; restore will not replace it.")}
            if current != record.change.previous {try backend.write(record.change.previous)}
            guard try backend.read()==record.change.previous else {throw RestoreError(.verificationFailed,"The previous Finder preference did not restore exactly.")}
            record.phase = .restored;try persist(record)
        }
        return await finish(restartApproved:restartApproved,note:"Previous Finder visibility preference restored.")
    }
    private func finish(restartApproved:Bool,note:String) async -> FinderVisibilityResult {
        guard restartApproved else {return .init(restarted:false,requiresRestart:true,note:note+" Restart Finder when ready to apply its display change.")}
        let restarted=await backend.restart()
        return .init(restarted:restarted,requiresRestart:!restarted,note:note+(restarted ? " Finder restarted.":" Finder restart was refused or failed; the saved preference is retained."))
    }
    private func persist(_ record:SavedVisibilityChange) throws {
        if let url=recordURL {
            let parent=try FileSystemPath.canonicalDirectory(url.deletingLastPathComponent());try SecureFS.privateDirectory(parent)
            let path=parent.appendingPathComponent(url.lastPathComponent),data=try JSONEncoder().encode(record)
            try data.write(to:path,options:.atomic)
            let directory=try SecureFS.directory(parent);defer {close(directory)}
            let fd=openat(directory,path.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open retained Finder preference")};defer {close(fd)}
            try SecureFS.restrict(fd,directory:false)
            guard fsync(fd)==0,fsync(directory)==0 else {throw SecureFS.error("Sync retained Finder preference")}
        }
        retained=record
    }
    private func load() throws -> SavedVisibilityChange? {
        if let retained {return retained}
        guard let url=recordURL,SecureFS.exists(url) else {return nil}
        let snapshot=try FileIdentityReader().snapshot(at:url)
        guard snapshot.kind == .regular,snapshot.ownerID==getuid(),snapshot.permissions & 0o077==0,snapshot.id.size<=65536 else {throw RestoreError(.unsupported,"The retained Finder preference record is not a private bounded file.")}
        let parent=try SecureFS.directory(try FileSystemPath.canonicalDirectory(url.deletingLastPathComponent()));defer {close(parent)}
        let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Read retained Finder preference")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? handle.close()}
        let data=try handle.read(upToCount:65537) ?? Data()
        guard data.count<=65536 else {throw RestoreError(.unsupported,"The retained Finder preference record exceeds its bound.")}
        let record=try JSONDecoder().decode(SavedVisibilityChange.self,from:data)
        guard record.schema==1 else {throw RestoreError(.unsupported,"Unknown Finder preference record schema.")}
        retained=record;return record
    }
}
private enum VisibilityRecordPhase:String,Codable {case prepared,applied,restored}
private struct SavedVisibilityChange:Codable {let schema:Int,change:FinderVisibilityChange;var phase:VisibilityRecordPhase}
