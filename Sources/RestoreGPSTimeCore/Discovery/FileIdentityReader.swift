import Foundation
import Darwin
import CryptoKit

public struct FileIdentityReader {
    public init() {}
    public func snapshot(at url: URL) throws -> FileSnapshot {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { throw RestoreError(.io,"Cannot inspect \(url.lastPathComponent): \(String(cString:strerror(errno)))") }
        let mode = st.st_mode & mode_t(S_IFMT)
        var kind: FileKind = mode == mode_t(S_IFLNK) ? .symlink : (mode == mode_t(S_IFDIR) ? .directory : .regular)
        if mode != mode_t(S_IFREG) && mode != mode_t(S_IFDIR) && mode != mode_t(S_IFLNK) { kind = .unavailable }
        if st.st_flags & UInt32(SF_DATALESS) != 0 { kind = .unavailable }
        if kind == .directory, (try? url.resourceValues(forKeys:[.isPackageKey]).isPackage) == true { kind = .package }
        let values = kind == .symlink ? nil : try? url.resourceValues(forKeys:[.volumeUUIDStringKey,.ubiquitousItemDownloadingStatusKey])
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded { kind = .unavailable }
        let id = SourceID(device:UInt64(UInt32(bitPattern:st.st_dev)),inode:UInt64(st.st_ino),size:UInt64(max(0,st.st_size)),modified:date(st.st_mtimespec),changed:date(st.st_ctimespec),linkCount:UInt64(st.st_nlink),volumeID:values?.volumeUUIDString ?? "device:\(st.st_dev)")
        let attrs = (kind == .regular || kind == .directory || kind == .package) ? try readXattrs(url) : [:]
        let hashes = attrs.mapValues { Self.hash($0) }
        return .init(url:url.standardizedFileURL,id:id,kind:kind,creationDate:date(st.st_birthtimespec),modificationDate:date(st.st_mtimespec),flags:st.st_flags,permissions:UInt16(st.st_mode & 0o7777),ownerID:st.st_uid,groupID:st.st_gid,xattrHashes:hashes,finderInfo:attrs["com.apple.FinderInfo"],aclText:(kind == .symlink || kind == .unavailable) ? nil : acl(url))
    }
    public func fingerprint(at url: URL) throws -> SourceFingerprint {
        let before = try snapshot(at:url)
        guard before.kind == .regular else {
            if before.kind == .directory { return .init(snapshot:before,contentHash:"") }
            throw RestoreError(.unsupported,"Only available ordinary files can be fingerprinted.")
        }
        let fd = Darwin.open(url.path,O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw RestoreError(.io,"Cannot read \(url.lastPathComponent).") }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer { try? handle.close() }
        var openStat=stat()
        guard fstat(fd,&openStat)==0, UInt64(openStat.st_ino)==before.id.inode, UInt64(UInt32(bitPattern:openStat.st_dev))==before.id.device else { throw RestoreError(.conflict,"File changed while opening it.") }
        var hasher=SHA256()
        while let data=try handle.read(upToCount:1_048_576),!data.isEmpty { try Task.checkCancellation();hasher.update(data:data) }
        let after=try snapshot(at:url)
        guard before==after else { throw RestoreError(.conflict,"File changed while calculating its fingerprint.") }
        return .init(snapshot:before,contentHash:hasher.finalize().map { String(format:"%02x",$0) }.joined())
    }
    public static func hash(_ data: Data) -> ContentHash { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    private func date(_ ts: timespec) -> Date { Date(timeIntervalSince1970:Double(ts.tv_sec)+Double(ts.tv_nsec)/1_000_000_000) }
    private func readXattrs(_ url: URL) throws -> [String:Data] {
        let count=listxattr(url.path,nil,0,XATTR_NOFOLLOW)
        if count<0 {
            if errno==ENOTSUP { return [:] }
            throw RestoreError(.io,"Cannot inventory file attributes.")
        }
        guard count<=1_048_576 else { throw RestoreError(.unsupported,"Attribute-name inventory exceeds the supported bound.") }
        var bytes=[CChar](repeating:0,count:count)
        if count>0, listxattr(url.path,&bytes,count,XATTR_NOFOLLOW) != count { throw RestoreError(.conflict,"Attributes changed while listing them.") }
        let names=bytes.split(separator:0).map { String(decoding:$0.map {UInt8(bitPattern:$0)},as:UTF8.self) }
        var result=[String:Data]();var total=0
        for name in names {
            let size=getxattr(url.path,name,nil,0,0,XATTR_NOFOLLOW)
            guard size>=0 else { throw RestoreError(.conflict,"An attribute changed while reading it.") }
            total += size
            guard total<=16_777_216 else { throw RestoreError(.unsupported,"File attributes exceed the bounded snapshot size; no changes were made.") }
            var data=Data(count:size)
            let read=data.withUnsafeMutableBytes { getxattr(url.path,name,$0.baseAddress,size,0,XATTR_NOFOLLOW) }
            guard read==size else { throw RestoreError(.conflict,"An attribute changed while reading it.") }
            result[name]=data
        }
        return result
    }
    private func acl(_ url:URL) -> String? {
        guard let value=acl_get_file(url.path,ACL_TYPE_EXTENDED) else { return nil }
        defer { acl_free(UnsafeMutableRawPointer(value)) }
        var count:ssize_t=0
        guard let text=acl_to_text(value,&count) else { return nil }
        defer { acl_free(text) }
        return String(cString:text)
    }
}
