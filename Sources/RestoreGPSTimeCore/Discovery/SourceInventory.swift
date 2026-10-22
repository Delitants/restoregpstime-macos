import Foundation

public struct DiscoveryOptions: Sendable {
    public var recursive = false
    public var includeFiles = true
    public var includeFolders = true
    public var includeHidden = false
    public var excludedRoots: [URL] = []
    public init() {}
}
public struct ExcludedSource: Sendable { public let url: URL; public let reason: String }
public struct DiscoveryResult: Sendable { public let snapshots: [FileSnapshot]; public let excluded: [ExcludedSource] }
public struct InspectedItem: Codable,Equatable,Sendable {
    public let snapshot: FileSnapshot
    public let metadata: MetadataDocument
    public var dateResolution:DateResolution?
    public var place:PlaceMatch?
    public init(snapshot: FileSnapshot, metadata: MetadataDocument,dateResolution:DateResolution?=nil,place:PlaceMatch?=nil) { self.snapshot = snapshot; self.metadata = metadata;self.dateResolution=dateResolution;self.place=place }
}
public struct SourceInventory {
    public init() {}
    public func scan(urls: [URL], options: DiscoveryOptions) async -> DiscoveryResult {
        let worker=Task.detached(priority:.userInitiated) { Self.scanBlocking(urls:urls,options:options) }
        return await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
    }
    private static func scanBlocking(urls:[URL],options:DiscoveryOptions) -> DiscoveryResult {
        var snapshots=[FileSnapshot](),excluded=[ExcludedSource](),seen=Set<String>()
        let reader=FileIdentityReader()
        func visit(_ url:URL, explicitlySelected:Bool) {
            if Task.isCancelled { return }
            let path=url.standardizedFileURL.path
            if options.excludedRoots.contains(where:{ $0.standardizedFileURL.path=="/" || path==$0.standardizedFileURL.path || path.hasPrefix($0.standardizedFileURL.path+"/") }) {
                excluded.append(.init(url:url,reason:"Output/recovery scope is excluded."));return
            }
            if !explicitlySelected && !options.includeHidden && url.lastPathComponent.hasPrefix(".") { excluded.append(.init(url:url,reason:"Hidden item."));return }
            do {
                let snapshot=try reader.snapshot(at:url)
                guard ![FileKind.symlink,.package,.unavailable].contains(snapshot.kind) else { excluded.append(.init(url:url,reason:"\(snapshot.kind.rawValue) items are not traversed."));return }
                guard seen.insert(snapshot.id.physicalKey).inserted else { excluded.append(.init(url:url,reason:"Duplicate physical file."));return }
                if snapshot.kind == .regular && options.includeFiles { snapshots.append(snapshot) }
                if snapshot.kind == .directory {
                    if options.includeFolders { snapshots.append(snapshot) }
                    if options.recursive {
                        for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).sorted(by:{$0.path<$1.path}) { visit(child,explicitlySelected:false) }
                    }
                }
            } catch { excluded.append(.init(url:url,reason:error.localizedDescription)) }
        }
        for url in urls { visit(url.standardizedFileURL,explicitlySelected:true) }
        return .init(snapshots:snapshots,excluded:excluded)
    }
}
