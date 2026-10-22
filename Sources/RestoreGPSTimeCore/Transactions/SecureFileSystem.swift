import Foundation
import Darwin

// Paths passed here are frozen canonical paths. Every component is opened without following links.
enum SecureFS {
    static func error(_ operation:String)->RestoreError {.init(.io,"\(operation): \(String(cString:strerror(errno)))")}
    static func directory(_ url:URL,create:Bool=false,mode:mode_t=0o755) throws -> Int32 {
        guard url.isFileURL,url.path.hasPrefix("/"),!url.path.utf8.contains(0) else {throw RestoreError(.invalidInput,"Invalid local directory path.")}
        var fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC)
        guard fd>=0 else {throw error("Open filesystem root")}
        do {
            for component in url.path.split(separator:"/") {
                let part=String(component)
                guard part != ".",part != ".." else {throw RestoreError(.invalidInput,"Directory traversal is not allowed.")}
                if create && mkdirat(fd,part,mode) != 0 && errno != EEXIST {throw error("Create directory")}
                let next=openat(fd,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                guard next>=0 else {throw error("Open directory component \(part) without links (\(url.path))")}
                close(fd);fd=next
            }
            return fd
        } catch {close(fd);throw error}
    }
    static func canonical(_ url:URL) throws -> URL {try FileSystemPath.canonicalDirectory(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent)}
    static func privateDirectory(_ url:URL) throws {
        let parent=try directory(url.deletingLastPathComponent());defer {close(parent)}
        let created=mkdirat(parent,url.lastPathComponent,0o700)==0
        if !created && errno != EEXIST {throw error("Create private recovery directory")}
        let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw error("Open private directory")};defer {close(fd)}
        if created {try restrict(fd,directory:true)}
        var st=stat();guard fstat(fd,&st)==0,st.st_uid==getuid(),st.st_mode & 0o077 == 0 else {throw RestoreError(.unsupported,"Recovery directories must be owned by this user and private.")}
        let snapshot=try FileIdentityReader().snapshot(at:url)
        if let acl=snapshot.aclText,acl.split(separator:"\n").contains(where:{!$0.hasPrefix("!#acl") && !$0.isEmpty}) {throw RestoreError(.unsupported,"Recovery directories cannot grant extended access to other accounts.")}
    }
    static func restrict(_ fd:Int32,directory:Bool) throws {
        guard fchflags(fd,0)==0 else {throw error("Clear flags on private evidence")}
        guard let acl=acl_init(0) else {throw error("Create private ACL")};defer {acl_free(UnsafeMutableRawPointer(acl))}
        guard acl_set_fd(fd,acl)==0,fchmod(fd,directory ? 0o700:0o600)==0 else {throw error("Protect private evidence")}
    }
    static func dates(_ snapshot:FileSnapshot,fd:Int32) throws {
        func ts(_ date:Date)->timespec {let seconds=floor(date.timeIntervalSince1970);return timespec(tv_sec:Int(seconds),tv_nsec:Int((date.timeIntervalSince1970-seconds)*1e9))}
        var list=attrlist();list.bitmapcount=UInt16(ATTR_BIT_MAP_COUNT);list.commonattr=attrgroup_t(ATTR_CMN_CRTIME|ATTR_CMN_MODTIME)
        var values=[ts(snapshot.creationDate),ts(snapshot.modificationDate)]
        let result=values.withUnsafeMutableBytes {fsetattrlist(fd,&list,$0.baseAddress,$0.count,0)}
        guard result==0 else {throw error("Preserve filesystem dates")}
    }
    static func copy(_ expected:SourceFingerprint,from source:URL,to destination:URL,vault:Bool=false) throws -> SourceFingerprint {
        let sourceParent=try directory(source.deletingLastPathComponent()),targetParent=try directory(destination.deletingLastPathComponent());defer {close(sourceParent);close(targetParent)}
        let isDirectory=expected.snapshot.kind == .directory
        let input=openat(sourceParent,source.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|(isDirectory ? O_DIRECTORY:0))
        guard input>=0 else {throw error("Open original")};defer {close(input)}
        var st=stat();guard fstat(input,&st)==0,UInt64(st.st_ino)==expected.snapshot.id.inode,UInt64(UInt32(bitPattern:st.st_dev))==expected.snapshot.id.device else {throw RestoreError(.conflict,"The original changed while opening it.")}
        let output:Int32
        if isDirectory {
            guard mkdirat(targetParent,destination.lastPathComponent,0o700)==0 else {throw error("Create directory stage")}
            output=openat(targetParent,destination.lastPathComponent,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        } else {output=openat(targetParent,destination.lastPathComponent,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)}
        guard output>=0 else {throw error("Create independent stage")};defer {close(output)}
        if !isDirectory {
            var buffer=[UInt8](repeating:0,count:1_048_576)
            while true {
                try Task.checkCancellation()
                let count=read(input,&buffer,buffer.count)
                if count==0 {break};if count<0 {if errno==EINTR {continue};throw error("Read original")}
                try buffer.withUnsafeBytes {bytes in
                    var offset=0
                    while offset<count {let written=write(output,bytes.baseAddress!.advanced(by:offset),count-offset);if written<0 && errno==EINTR {continue};guard written>0 else {throw error("Write stage")};offset+=written}
                }
            }
        }
        guard fchown(output,expected.snapshot.ownerID,expected.snapshot.groupID)==0 else {throw error("Preserve ownership")}
        guard fcopyfile(input,output,nil,copyfile_flags_t(COPYFILE_XATTR|COPYFILE_ACL))==0 else {throw error("Preserve extended attributes and ACL")}
        guard fchmod(output,mode_t(expected.snapshot.permissions))==0 else {throw error("Preserve permissions")}
        try dates(expected.snapshot,fd:output)
        guard fchflags(output,expected.snapshot.flags & ~UInt32(UF_IMMUTABLE))==0,fsync(output)==0 else {throw error("Sync copied attributes")}
        let copied=try FileIdentityReader().fingerprint(at:destination)
        guard copied.contentHash==expected.contentHash,copied.snapshot.xattrHashes==expected.snapshot.xattrHashes,copied.snapshot.permissions==expected.snapshot.permissions,copied.snapshot.aclText==expected.snapshot.aclText,abs(copied.snapshot.creationDate.timeIntervalSince(expected.snapshot.creationDate))<0.00001,abs(copied.snapshot.modificationDate.timeIntervalSince(expected.snapshot.modificationDate))<0.00001 else {throw RestoreError(.verificationFailed,"The target filesystem did not preserve the original data and attributes.")}
        if vault {try restrict(output,directory:isDirectory);guard fsync(output)==0 else {throw error("Sync retained original")}}
        return try FileIdentityReader().fingerprint(at:destination)
    }
    static func rename(_ from:URL,_ to:URL,swap:Bool=false) throws {
        let a=try directory(from.deletingLastPathComponent()),b=try directory(to.deletingLastPathComponent());defer {close(a);close(b)}
        guard renameatx_np(a,from.lastPathComponent,b,to.lastPathComponent,UInt32(swap ? RENAME_SWAP:RENAME_EXCL))==0 else {throw error(swap ? "Exchange original and verified stage":"Commit without replacing an existing file")}
        guard fsync(a)==0,fsync(b)==0 else {throw error("Sync committed directory entries")}
    }
    static func flags(_ url:URL,_ flags:UInt32) throws {
        let parent=try directory(url.deletingLastPathComponent());defer {close(parent)}
        let fd=openat(parent,url.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw error("Open flags target")};defer {close(fd)}
        guard fchflags(fd,flags)==0,fsync(fd)==0 else {throw error("Set and sync selected file flags")}
    }
    static func matches(_ actual:SourceFingerprint,_ expected:SourceFingerprint,ignoreChangeTime:Bool=false,flags:UInt32?=nil)->Bool {
        let a=actual.snapshot,b=expected.snapshot
        return actual.contentHash==expected.contentHash && a.id.physicalKey==b.id.physicalKey && a.id.size==b.id.size && a.kind==b.kind && a.creationDate==b.creationDate && a.modificationDate==b.modificationDate && a.flags==(flags ?? b.flags) && a.permissions==b.permissions && a.ownerID==b.ownerID && a.groupID==b.groupID && a.xattrHashes==b.xattrHashes && a.aclText==b.aclText && (ignoreChangeTime || a.id.changed==b.id.changed)
    }
    static func attributesEqual(_ a:FileSnapshot,_ b:FileSnapshot,flags:UInt32?=nil)->Bool {
        a.creationDate==b.creationDate && a.modificationDate==b.modificationDate && a.kind==b.kind && a.flags==(flags ?? b.flags) && a.permissions==b.permissions && a.ownerID==b.ownerID && a.groupID==b.groupID && a.xattrHashes==b.xattrHashes && a.aclText==b.aclText
    }
    static func stableDirectoryAttributes(_ a:FileSnapshot,_ b:FileSnapshot)->Bool {
        a.kind==b.kind && a.flags==b.flags && a.permissions==b.permissions && a.ownerID==b.ownerID && a.groupID==b.groupID && a.xattrHashes==b.xattrHashes && a.aclText==b.aclText
    }
    static func exists(_ url:URL)->Bool {var st=stat();return lstat(url.path,&st)==0}
    static func requireSpace(at directory:URL,bytes:UInt64) throws {
        var stat=statvfs();guard statvfs(directory.path,&stat)==0 else {throw error("Read available storage")}
        let capacity=UInt64(stat.f_bavail).multipliedReportingOverflow(by:UInt64(stat.f_frsize))
        guard !capacity.overflow,capacity.partialValue>bytes else {throw RestoreError(.io,"Insufficient free space for verified originals and staging.")}
    }
}

extension SecureFS {
    static func applyMetadata(_ snapshot:FileSnapshot,from source:URL,to target:URL) throws {
        let a=try directory(source.deletingLastPathComponent()),b=try directory(target.deletingLastPathComponent());defer {close(a);close(b)}
        let input=openat(a,source.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC),output=openat(b,target.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard input>=0,output>=0 else {if input>=0 {close(input)};if output>=0 {close(output)};throw error("Open attribute restoration")};defer {close(input);close(output)}
        let current=try FileIdentityReader().snapshot(at:target)
        if current.isLocked {guard fchflags(output,current.flags & ~UInt32(UF_IMMUTABLE))==0 else {throw error("Unlock owned restoration target")}}
        for name in current.xattrHashes.keys where snapshot.xattrHashes[name]==nil {guard fremovexattr(output,name,0)==0 else {throw error("Restore exact attribute inventory")}}
        guard fcopyfile(input,output,nil,copyfile_flags_t(COPYFILE_XATTR))==0,fchown(output,snapshot.ownerID,snapshot.groupID)==0 else {throw error("Restore extended attributes and ownership")}
        if let text=snapshot.aclText {
            guard let acl=acl_from_text(text) else {throw error("Read saved ACL")};defer {acl_free(UnsafeMutableRawPointer(acl))}
            guard acl_set_fd(output,acl)==0 else {throw error("Restore ACL")}
        } else {
            guard let acl=acl_init(0) else {throw error("Create empty saved ACL")};defer {acl_free(UnsafeMutableRawPointer(acl))}
            guard acl_set_fd(output,acl)==0 else {throw error("Restore empty ACL")}
        }
        guard fchmod(output,mode_t(snapshot.permissions))==0 else {throw error("Restore original permissions")}
        try dates(snapshot,fd:output)
        guard fchflags(output,snapshot.flags & ~UInt32(UF_IMMUTABLE))==0,fsync(output)==0 else {throw error("Sync restored attributes")}
    }
}
