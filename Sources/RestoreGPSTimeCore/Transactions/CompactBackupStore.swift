import Foundation
import CryptoKit
import SQLite3
import Darwin

struct CompactBackupPayload:Codable {
    let original:SourceFingerprint
    let outputHash:String
    let xattrs:[String:Data]
    let delta:ReverseDelta?
    func applyAttributes(to target:URL) throws {
        let snapshot=original.snapshot,fd=open(target.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw SecureFS.error("Open compact attributes target")};defer {close(fd)}
        let current=try FileIdentityReader().snapshot(at:target)
        if current.isLocked {guard fchflags(fd,current.flags & ~UInt32(UF_IMMUTABLE))==0 else {throw SecureFS.error("Unlock reconstruction")}}
        for name in current.xattrHashes.keys where xattrs[name]==nil {guard fremovexattr(fd,name,0)==0 else {throw SecureFS.error("Remove newer reconstruction attribute")}}
        for (name,data) in xattrs {guard data.withUnsafeBytes({fsetxattr(fd,name,$0.baseAddress,data.count,0,0)})==0 else {throw SecureFS.error("Restore raw extended attribute")}}
        guard fchown(fd,snapshot.ownerID,snapshot.groupID)==0 else {throw SecureFS.error("Restore compact ownership")}
        let acl=snapshot.aclText.flatMap {acl_from_text($0)} ?? acl_init(0)
        guard let acl else {throw SecureFS.error("Decode compact ACL")};defer {acl_free(UnsafeMutableRawPointer(acl))}
        guard acl_set_fd(fd,acl)==0,fchmod(fd,mode_t(snapshot.permissions))==0 else {throw SecureFS.error("Restore compact ACL and permissions")}
        try SecureFS.dates(snapshot,fd:fd)
        guard fchflags(fd,snapshot.flags & ~UInt32(UF_IMMUTABLE))==0,fsync(fd)==0 else {throw SecureFS.error("Sync compact attributes")}
    }
}

/// SQLite is stored privately and synced before any original directory entry moves.
/// Each opaque payload is SHA-256 bound by the independently synced group journal.
struct CompactBackupStore {
    let journal:RecoveryJournal
    private var url:URL {journal.batchDirectory.appendingPathComponent("compact.sqlite")}
    func capture(_ record:inout RecoveryRecord) throws {
        guard record.options.mode == .modifyInPlace,record.options.effectiveBackupMode == .metadata else {return}
        for index in record.members.indices where record.members[index].item.mutation.outputKind == .sourceCopy {
            let member=record.members[index],original=member.item.source,source=try SecureFS.canonical(original.snapshot.url)
            guard let stage=member.stageURL,let staged=member.staged else {throw RestoreError(.verificationFailed,"Compact backup requires verified staging.")}
            let fd=open(source.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);guard fd>=0 else {throw SecureFS.error("Open original attributes")};defer {close(fd)}
            var raw=[String:Data](),total=0
            for name in original.snapshot.xattrHashes.keys {
                let size=fgetxattr(fd,name,nil,0,0,0)
                guard size>=0,size<=16*1024*1024,total+size<=16*1024*1024 else {throw ReverseDelta.tooLarge()}
                var data=Data(count:size)
                guard data.withUnsafeMutableBytes({fgetxattr(fd,name,$0.baseAddress,size,0,0)})==size else {throw RestoreError(.conflict,"Original attributes changed during compact backup.")}
                raw[name]=data;total+=size
            }
            let delta=original.snapshot.kind == .directory ? nil:try ReverseDelta.capture(original:source,output:stage)
            let payload=CompactBackupPayload(original:original,outputHash:staged.contentHash,xattrs:raw,delta:delta)
            let data=try JSONEncoder().encode(payload)
            guard data.count<=ReverseDelta.maximumPayload else {throw ReverseDelta.tooLarge()}
            // Directory timestamps may have been changed by this batch's descendants;
            // original raw xattrs/ACLs and the frozen snapshot remain authoritative.
            let current=try FileIdentityReader().fingerprint(at:source)
            if original.snapshot.kind != .directory {guard current==original else {throw RestoreError(.conflict,"Original changed during compact backup.")}}
            try store(data,group:record.groupID,index:index)
            record.members[index].compactHash=Self.hash(data)
        }
    }
    func payload(_ member:RecoveryMember,record:RecoveryRecord) throws -> CompactBackupPayload {
        guard let index=record.members.firstIndex(where:{$0.item.name.sourceKey==member.item.name.sourceKey}),let expected=member.compactHash else {throw RestoreError(.recoveryNeeded,"Compact restoration data is unavailable.")}
        let data=try fetch(group:record.groupID,index:index)
        guard Self.hash(data)==expected else {throw RestoreError(.verificationFailed,"Compact database changed; undo stopped.")}
        let payload=try JSONDecoder().decode(CompactBackupPayload.self,from:data)
        guard payload.original==member.item.source,payload.outputHash==member.staged?.contentHash else {throw RestoreError(.verificationFailed,"Compact database identity mismatch.")}
        return payload
    }
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    private func database<T>(create:Bool,_ action:(OpaquePointer)throws->T) throws -> T {
        let parent=try SecureFS.directory(journal.batchDirectory);defer {close(parent)}
        let fd=openat(parent,url.lastPathComponent,O_RDWR|O_NOFOLLOW|O_CLOEXEC|(create ? O_CREAT:0),0o600)
        guard fd>=0 else {throw SecureFS.error("Open private compact database")};defer {close(fd)}
        var st=stat();guard fstat(fd,&st)==0,st.st_uid==getuid(),st.st_nlink==1,st.st_mode&S_IFMT==S_IFREG,st.st_mode&0o077==0 else {throw RestoreError(.conflict,"Unsafe compact database.")}
        var db:OpaquePointer?
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK,let db else {if let db {sqlite3_close(db)};throw RestoreError(.io,"Open compact SQLite database failed.")}
        defer {sqlite3_close(db)}
        sqlite3_limit(db,SQLITE_LIMIT_LENGTH,Int32(ReverseDelta.maximumPayload+1_048_576))
        func execute(_ sql:String) throws {guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else {throw RestoreError(.io,"Compact database operation failed: "+String(cString:sqlite3_errmsg(db)))}}
        try execute("PRAGMA trusted_schema=OFF; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;")
        if create {try execute("CREATE TABLE IF NOT EXISTS originals (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")}
        let value=try action(db)
        guard fsync(fd)==0,fsync(parent)==0 else {throw SecureFS.error("Sync compact database")}
        return value
    }
    private func store(_ data:Data,group:UUID,index:Int) throws {
        try database(create:true) {db in
            var statement:OpaquePointer?;defer {sqlite3_finalize(statement)}
            guard sqlite3_prepare_v2(db,"INSERT OR REPLACE INTO originals VALUES (?,?)",-1,&statement,nil)==SQLITE_OK else {throw RestoreError(.io,"Prepare compact database insert failed.")}
            let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self),key="\(group.uuidString)/\(index)"
            guard sqlite3_bind_text(statement,1,key,-1,transient)==SQLITE_OK,data.withUnsafeBytes({sqlite3_bind_blob(statement,2,$0.baseAddress,Int32(data.count),transient)})==SQLITE_OK,sqlite3_step(statement)==SQLITE_DONE else {throw RestoreError(.io,"Persist compact database failed.")}
        }
    }
    private func fetch(group:UUID,index:Int) throws -> Data {
        try database(create:false) {db in
            var statement:OpaquePointer?;defer {sqlite3_finalize(statement)}
            guard sqlite3_prepare_v2(db,"SELECT payload FROM originals WHERE id=?",-1,&statement,nil)==SQLITE_OK else {throw RestoreError(.io,"Read compact database failed.")}
            let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self),key="\(group.uuidString)/\(index)"
            guard sqlite3_bind_text(statement,1,key,-1,transient)==SQLITE_OK,sqlite3_step(statement)==SQLITE_ROW else {throw RestoreError(.recoveryNeeded,"Compact database entry is missing.")}
            let size=Int(sqlite3_column_bytes(statement,0));guard size>0,size<=ReverseDelta.maximumPayload,let bytes=sqlite3_column_blob(statement,0) else {throw RestoreError(.invalidInput,"Invalid compact database payload.")}
            return Data(bytes:bytes,count:size)
        }
    }
}
