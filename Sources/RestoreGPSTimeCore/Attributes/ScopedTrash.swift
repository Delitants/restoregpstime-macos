import Foundation
import Darwin

public struct TrashScope:Sendable {
    public let roots:[URL],excludedRoots:[URL]
    public let recursive:Bool
    public init(roots:[URL],recursive:Bool=false,excludedRoots:[URL]=[]) {self.roots=roots;self.recursive=recursive;self.excludedRoots=excludedRoots}
}
public struct TrashExclusion:Codable,Sendable {public let url:URL,reason:String}
public struct TrashPlan:Codable,Sendable {
    public let id:UUID,candidates:[SourceFingerprint],anchors:[DestinationAnchor],scopeRoots:[URL],directoryRoots:Set<String>,recursive:Bool,excluded:[TrashExclusion]
}
public struct TrashResult:Codable,Sendable {
    public let source:URL,trashedURL:URL?,error:String?
    public var succeeded:Bool {trashedURL != nil && error==nil}
}
public protocol TrashBackend:Sendable {func trash(_ expected:SourceFingerprint) throws -> URL}
public struct ScopedTrash:Sendable {
    private let backend:any TrashBackend
    public init() {backend=SystemTrashBackend()}
    public init(backend:any TrashBackend) {self.backend=backend}
    public func preview(scope:TrashScope) async throws -> TrashPlan {
        let worker=Task.detached(priority:.userInitiated) {try Self.scan(scope)}
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
    public func execute(_ plan:TrashPlan) async -> [TrashResult] {
        let worker=Task.detached(priority:.userInitiated) {run(plan)}
        return await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
    }
    private static func hidden(_ snapshot:FileSnapshot)->Bool {
        snapshot.url.lastPathComponent.hasPrefix(".") || snapshot.flags & UInt32(UF_HIDDEN) != 0 || (snapshot.finderInfo.map {$0.count==32 && $0[8]&0x40 != 0} ?? false)
    }
    private static func scan(_ scope:TrashScope) throws -> TrashPlan {
        guard !scope.roots.isEmpty,scope.roots.count<=10000 else {throw RestoreError(.invalidInput,"Select a bounded set of cleanup files or folders.")}
        let reader=FileIdentityReader()
        var candidates=[SourceFingerprint](),excluded=[TrashExclusion](),anchors=[DestinationAnchor](),roots=[URL](),directories=Set<String>(),seen=Set<String>(),visits=0
        func visit(_ url:URL,depth:Int,root:Bool=false) throws {
            try Task.checkCancellation();visits+=1
            guard depth<=128,visits<=100000 else {throw RestoreError(.unsupported,"Cleanup scope exceeds its depth or item bound. Choose a narrower folder.")}
            guard seen.insert(url.path).inserted else {return}
            if scope.excludedRoots.contains(where:{BatchPlanner.isWithin(url,$0)}) {excluded.append(.init(url:url,reason:"Output/recovery scope is excluded."));return}
            do {
                let snapshot=try reader.snapshot(at:url)
                switch snapshot.kind {
                case .regular:
                    if hidden(snapshot) {candidates.append(try reader.fingerprint(at:url))}
                case .directory:
                    if url.lastPathComponent.hasPrefix(".RestoreGPSTime-") {excluded.append(.init(url:url,reason:"Private transaction directories are excluded."));return}
                    if root || scope.recursive {
                        for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).sorted(by:{$0.path<$1.path}) {try visit(child,depth:depth+1)}
                    }
                default:excluded.append(.init(url:url,reason:"Packages, symlinks and unavailable items are not cleaned."))
                }
            } catch is CancellationError {throw CancellationError()}
            catch let error as RestoreError where error.code == .unsupported {throw error}
            catch {excluded.append(.init(url:url,reason:error.localizedDescription))}
        }
        for requested in scope.roots {
            let canonical=try SecureFS.canonical(requested),snapshot=try reader.snapshot(at:canonical)
            guard [.regular,.directory].contains(snapshot.kind) else {excluded.append(.init(url:requested,reason:"Only ordinary files and folders are valid cleanup roots."));continue}
            let parent=snapshot.kind == .directory ? canonical:canonical.deletingLastPathComponent(),identity=try reader.snapshot(at:parent)
            anchors.append(.init(requestedURL:parent,resolvedURL:try FileSystemPath.canonicalDirectory(parent),identity:identity.id))
            roots.append(canonical);if snapshot.kind == .directory {directories.insert(canonical.path)}
            try visit(canonical,depth:0,root:true)
        }
        return .init(id:UUID(),candidates:candidates.sorted {$0.snapshot.url.path<$1.snapshot.url.path},anchors:anchors,scopeRoots:roots,directoryRoots:directories,recursive:scope.recursive,excluded:excluded)
    }
    private func run(_ plan:TrashPlan)->[TrashResult] {
        var results=[TrashResult]()
        for candidate in plan.candidates {
            var source=candidate.snapshot.url
            var destination:URL?
            do {
                try Task.checkCancellation()
                source=try SecureFS.canonical(source)
                guard plan.scopeRoots.contains(where:{$0.path==source.path || plan.directoryRoots.contains($0.path) && (plan.recursive ? BatchPlanner.isWithin(source,$0):source.deletingLastPathComponent().path==$0.path)}) else {throw RestoreError(.conflict,"The cleanup item is outside the frozen scope.")}
                for anchor in plan.anchors {
                    let current=try FileIdentityReader().snapshot(at:anchor.requestedURL)
                    guard current.kind == .directory,current.id.physicalKey==anchor.identity.physicalKey,try FileSystemPath.canonicalDirectory(anchor.requestedURL).path==anchor.resolvedURL.path else {throw RestoreError(.conflict,"The cleanup root changed after preview.")}
                }
                let fd=try SecureFS.directory(source.deletingLastPathComponent());close(fd)
                guard candidate.snapshot.kind == .regular,Self.hidden(candidate.snapshot),try FileIdentityReader().fingerprint(at:source)==candidate else {throw RestoreError(.conflict,"The hidden file changed after preview.")}
                destination=try backend.trash(candidate)
                try Self.verifyPayload(candidate,at:destination!)
                guard !SecureFS.exists(source) else {throw RestoreError(.verificationFailed,"The source path is occupied after Trash. Keep the destination receipt and review the source.")}
                results.append(.init(source:source,trashedURL:destination,error:nil))
            } catch {results.append(.init(source:source,trashedURL:destination,error:error.localizedDescription))}
        }
        return results
    }
    private static func verifyPayload(_ expected:SourceFingerprint,at destination:URL) throws {
        // Trash legitimately adds macl/provenance xattrs. Bind a stored-byte hash to one
        // open file, its size/mtime and the destination inode; ctime is not data integrity.
        let reader=try BoundedMediaReader(destination),fd=reader.handle.fileDescriptor
        var before=stat(),after=stat(),path=stat()
        guard fstat(fd,&before)==0,reader.size==expected.snapshot.id.size else {throw RestoreError(.verificationFailed,"Trashed data size differs from preview; retain the receipt.")}
        let hash=try reader.hash(0,reader.size)
        guard fstat(fd,&after)==0,lstat(destination.path,&path)==0,before.st_ino==after.st_ino,after.st_ino==path.st_ino,after.st_dev==path.st_dev,before.st_size==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,hash==expected.contentHash else {throw RestoreError(.verificationFailed,"Trashed payload could not be verified; retain the destination receipt.")}
    }
}

public struct SystemTrashBackend:TrashBackend {
    public init() {}
    public func trash(_ expected:SourceFingerprint) throws -> URL {
        var coordinationError:NSError?,outcome:Result<URL,Error>?
        NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:expected.snapshot.url,options:.forDeleting,error:&coordinationError) {_ in
            outcome=Result {
                guard try FileIdentityReader().fingerprint(at:expected.snapshot.url)==expected else {throw RestoreError(.conflict,"The cleanup file changed immediately before Trash.")}
                var result:NSURL?
                try FileManager.default.trashItem(at:expected.snapshot.url,resultingItemURL:&result)
                guard let url=result as URL? else {throw RestoreError(.verificationFailed,"System Trash returned no recoverable destination receipt.")}
                return url
            }
        }
        if let error=coordinationError {throw RestoreError(.io,"Trash coordination failed: "+error.localizedDescription)}
        guard let outcome else {throw RestoreError(.io,"Trash did not grant file coordination.")};return try outcome.get()
    }
}
