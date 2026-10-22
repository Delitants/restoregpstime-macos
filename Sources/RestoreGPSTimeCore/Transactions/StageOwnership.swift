import Foundation
import Darwin

final class StageOwnership:@unchecked Sendable {
    static let shared=StageOwnership()
    private struct Permit {let root:URL,rootKey:String,fileKey:String,kind:FileKind}
    private let lock=NSLock()
    private var permits=[String:Permit]()
    func register(_ url:URL,root:URL) throws {
        let canonical=try SecureFS.canonical(url),directory=try FileSystemPath.canonicalDirectory(root)
        let rootSnapshot=try FileIdentityReader().snapshot(at:directory),file=try FileIdentityReader().snapshot(at:canonical)
        guard canonical.deletingLastPathComponent().path==directory.path,rootSnapshot.kind == .directory,rootSnapshot.permissions & 0o077==0,rootSnapshot.ownerID==getuid(),[.regular,.directory].contains(file.kind),file.kind == .directory || file.id.linkCount==1 else {throw RestoreError(.invalidInput,"An attribute stage must be an independent file or directory in a private transaction directory.")}
        lock.lock();defer {lock.unlock()};permits[canonical.path] = .init(root:directory,rootKey:rootSnapshot.id.physicalKey,fileKey:file.id.physicalKey,kind:file.kind)
    }
    func require(_ url:URL,kind:FileKind?=nil) throws {
        let canonical=try SecureFS.canonical(url)
        lock.lock();let permit=permits[canonical.path];lock.unlock()
        guard let permit else {throw RestoreError(.invalidInput,"Metadata writing is restricted to owned transaction stages.")}
        let root=try FileIdentityReader().snapshot(at:permit.root),file=try FileIdentityReader().snapshot(at:canonical)
        guard root.kind == .directory,root.id.physicalKey==permit.rootKey,root.ownerID==getuid(),root.permissions & 0o077==0,file.kind==permit.kind,kind==nil || file.kind==kind,file.id.physicalKey==permit.fileKey,file.kind == .directory || file.id.linkCount==1 else {throw RestoreError(.conflict,"The authorized stage or its private directory changed.")}
    }
    func refresh(_ url:URL) throws {
        let canonical=try SecureFS.canonical(url)
        lock.lock();let permit=permits[canonical.path];lock.unlock()
        guard let permit else {throw RestoreError(.invalidInput,"No metadata-stage ownership permit exists.")}
        let root=try FileIdentityReader().snapshot(at:permit.root)
        guard root.id.physicalKey==permit.rootKey,try FileIdentityReader().snapshot(at:canonical).kind==permit.kind else {throw RestoreError(.conflict,"The metadata stage directory or item kind changed during helper execution.")}
        try register(canonical,root:permit.root)
    }
    func remove(_ url:URL) {
        lock.lock();permits[url.path]=nil;lock.unlock()
    }
}
