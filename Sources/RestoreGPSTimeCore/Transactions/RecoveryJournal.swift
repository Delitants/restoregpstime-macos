import Foundation
import Darwin

public final class RecoveryJournal:@unchecked Sendable {
    public let root:URL,batchID:UUID
    private let lock=NSLock()
    let checkpoint:@Sendable(TransactionPoint)throws->Void
    public init(root:URL,batchID:UUID,checkpoint:@escaping @Sendable(TransactionPoint)throws->Void={_ in}) throws {
        let location=try FileSystemPath.existingAncestor(of:root)
        var resolved=try FileSystemPath.canonicalDirectory(location.parent)
        for component in location.components {resolved=resolved.appendingPathComponent(component,isDirectory:true)}
        self.root=resolved
        self.batchID=batchID;self.checkpoint=checkpoint
        let fd=try SecureFS.directory(self.root,create:true,mode:0o700);close(fd)
        var st=stat();guard lstat(self.root.path,&st)==0,st.st_uid==getuid(),st.st_mode & 0o022==0 else {throw RestoreError(.unsupported,"The recovery root must belong to this user and cannot be writable by other accounts.")}
        try SecureFS.privateDirectory(batchDirectory)
        try SecureFS.privateDirectory(batchDirectory.appendingPathComponent("groups"))
        try SecureFS.privateDirectory(batchDirectory.appendingPathComponent("originals"))
    }
    public var batchDirectory:URL {root.appendingPathComponent(batchID.uuidString)}
    public func recordURL(groupID:UUID)->URL {batchDirectory.appendingPathComponent("groups/\(groupID.uuidString).json")}
    public func persist(_ record:RecoveryRecord) throws {
        lock.lock();defer {lock.unlock()}
        guard record.schema==1,record.batchID==batchID else {throw RestoreError(.invalidInput,"Invalid recovery record identity.")}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(record)
        guard data.count<=67_108_864 else {throw RestoreError(.unsupported,"Recovery record exceeds its safety limit.")}
        let parent=try SecureFS.directory(batchDirectory.appendingPathComponent("groups"));defer {close(parent)}
        let temporary=".journal-\(UUID().uuidString).tmp",fd=openat(parent,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else {throw SecureFS.error("Create journal revision")};defer {close(fd)}
        try data.withUnsafeBytes {bytes in var offset=0;while offset<data.count {let n=write(fd,bytes.baseAddress!.advanced(by:offset),data.count-offset);if n<0 && errno==EINTR {continue};guard n>0 else {throw SecureFS.error("Write journal")};offset+=n}}
        try checkpoint(.beforeJournalSync)
        guard fsync(fd)==0,renameat(parent,temporary,parent,"\(record.groupID.uuidString).json")==0,fsync(parent)==0 else {throw SecureFS.error("Persist recovery journal")}
    }
    public func record(groupID:UUID) throws -> RecoveryRecord? {
        lock.lock();defer {lock.unlock()};return try readRecord(groupID)
    }
    private func readRecord(_ groupID:UUID) throws -> RecoveryRecord? {
        let parent=try SecureFS.directory(batchDirectory.appendingPathComponent("groups"));defer {close(parent)}
        let fd=openat(parent,"\(groupID.uuidString).json",O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        if fd<0 && errno==ENOENT {return nil}
        guard fd>=0 else {throw SecureFS.error("Open recovery manifest")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? handle.close()}
        var before=stat(),after=stat()
        guard fstat(fd,&before)==0,before.st_mode & S_IFMT==S_IFREG,before.st_nlink==1,before.st_uid==getuid(),before.st_mode & 0o077==0,before.st_size>=0,before.st_size<=67_108_864 else {throw RestoreError(.invalidInput,"Unsafe recovery manifest.")}
        let data=try handle.read(upToCount:67_108_865) ?? Data()
        guard data.count<=67_108_864,fstat(fd,&after)==0,before.st_size==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec else {throw RestoreError(.conflict,"Recovery manifest changed while reading it.")}
        let record=try JSONDecoder().decode(RecoveryRecord.self,from:data)
        guard record.schema==1,record.batchID==batchID,record.groupID==groupID else {throw RestoreError(.invalidInput,"Recovery manifest identity mismatch.")}
        return record
    }
    public func records() throws -> [RecoveryRecord] {
        lock.lock();defer {lock.unlock()}
        let directory=batchDirectory.appendingPathComponent("groups")
        return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter {$0.pathExtension=="json"}.sorted {$0.path<$1.path}.map {url in
            guard let id=UUID(uuidString:url.deletingPathExtension().lastPathComponent),let record=try readRecord(id) else {throw RestoreError(.conflict,"Recovery manifest disappeared or has an invalid name.")};return record
        }
    }
    public func incompleteRecords() throws -> [RecoveryRecord] {try records().filter {$0.phase != .committed && $0.phase != .restored}}
}
