import Foundation
import Darwin

final class StageOwnership:@unchecked Sendable {
    static let shared=StageOwnership()
    private struct Permit {let root:URL,rootKey:String,fileKey:String}
    private let lock=NSLock()
    private var permits=[String:Permit]()
    func register(_ url:URL,root:URL) throws {
        let canonical=try SecureFS.canonical(url),directory=try FileSystemPath.canonicalDirectory(root)
        let rootSnapshot=try FileIdentityReader().snapshot(at:directory),file=try FileIdentityReader().snapshot(at:canonical)
        guard canonical.deletingLastPathComponent().path==directory.path,rootSnapshot.kind == .directory,rootSnapshot.permissions & 0o077==0,rootSnapshot.ownerID==getuid(),file.kind == .regular,file.id.linkCount==1 else {throw RestoreError(.invalidInput,"A metadata stage must be an independent file in a private transaction directory.")}
        lock.lock();defer {lock.unlock()};permits[canonical.path] = .init(root:directory,rootKey:rootSnapshot.id.physicalKey,fileKey:file.id.physicalKey)
    }
    func require(_ url:URL) throws {
        let canonical=try SecureFS.canonical(url)
        lock.lock();let permit=permits[canonical.path];lock.unlock()
        guard let permit else {throw RestoreError(.invalidInput,"Metadata writing is restricted to owned transaction stages.")}
        let root=try FileIdentityReader().snapshot(at:permit.root),file=try FileIdentityReader().snapshot(at:canonical)
        guard root.kind == .directory,root.id.physicalKey==permit.rootKey,root.ownerID==getuid(),root.permissions & 0o077==0,file.kind == .regular,file.id.physicalKey==permit.fileKey,file.id.linkCount==1 else {throw RestoreError(.conflict,"The authorized metadata stage or its private directory changed.")}
    }
    func refresh(_ url:URL) throws {
        let canonical=try SecureFS.canonical(url)
        lock.lock();let permit=permits[canonical.path];lock.unlock()
        guard let permit else {throw RestoreError(.invalidInput,"No metadata-stage ownership permit exists.")}
        let root=try FileIdentityReader().snapshot(at:permit.root)
        guard root.id.physicalKey==permit.rootKey else {throw RestoreError(.conflict,"The metadata stage directory was replaced during helper execution.")}
        try register(canonical,root:permit.root)
    }
    func remove(_ url:URL) {
        lock.lock();permits[url.path]=nil;lock.unlock()
    }
}
