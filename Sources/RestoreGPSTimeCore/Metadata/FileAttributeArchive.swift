import Foundation
import Darwin

struct FileAttributeArchive {
    static func capture(_ stage:URL) throws -> URL {
        let canonical=try SecureFS.canonical(stage),snapshot=try FileIdentityReader().snapshot(at:canonical),root=canonical.deletingLastPathComponent()
        let parent=try FileIdentityReader().snapshot(at:root)
        guard [.regular,.directory].contains(snapshot.kind),parent.ownerID==getuid(),parent.permissions & 0o077==0 else {throw RestoreError(.invalidInput,"Attribute archives require a private transaction stage.")}
        let url=root.appendingPathComponent(".fs-attributes-\(UUID().uuidString)")
        let isDirectory=snapshot.kind == .directory
        if isDirectory {try SecureFS.privateDirectory(url)}
        let parentFD=try SecureFS.directory(root);defer {close(parentFD)}
        let input=openat(parentFD,canonical.lastPathComponent,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|(isDirectory ? O_DIRECTORY:0));guard input>=0 else {throw SecureFS.error("Open stage attributes")};defer {close(input)}
        let output=openat(parentFD,url.lastPathComponent,isDirectory ? O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC:O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard output>=0 else {throw SecureFS.error("Create attribute archive")};defer {close(output)}
        try SecureFS.copyExtendedAttributes(from:input,to:output)
        try SecureFS.restrict(output,directory:isDirectory)
        guard fsync(output)==0,try FileIdentityReader().snapshot(at:url).xattrHashes==snapshot.xattrHashes else {throw RestoreError(.verificationFailed,"The attribute archive does not match its stage.")}
        return url
    }
}
