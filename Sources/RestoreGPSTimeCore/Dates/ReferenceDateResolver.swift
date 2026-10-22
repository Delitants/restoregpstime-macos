import Foundation

public struct ReferenceDateContext:Sendable {
    public var referenceRoot:URL?
    public var inputRoot:URL?
    public var allowBasenameFallback=false
    public var frozenNow:Date
    public var metadata:MetadataDocument?
    public var reader:MetadataReader?
    public var datePolicy=DatePolicy()
    public init(clock:any Clock=SystemClock()) { frozenNow=clock.now() }
}
public struct ReferenceDateResolver {
    public init() {}
    public func resolve(source:SourceChoice,snapshot:FileSnapshot,context:ReferenceDateContext) async throws -> DateResolution {
        switch source {
        case .fileCreation: return CaptureDateResolver.instant(snapshot.creationDate,source:"File creation date")
        case .fileModification: return CaptureDateResolver.instant(snapshot.modificationDate,source:"File modification date")
        case .specific(let date): return CaptureDateResolver.instant(date,source:"Specific date")
        case .current: return CaptureDateResolver.instant(context.frozenNow,source:"Current time frozen at preview")
        case .reset: return CaptureDateResolver.instant(Date(timeIntervalSince1970:-2_082_844_800),source:"Reset to 1904-01-01 UTC")
        case .filename(let pattern):
            let raw=try FilenameDateParser().parse(filename:snapshot.url.lastPathComponent,pattern:pattern)
            var policy=context.datePolicy;policy.source = .tag("Filename:CaptureDate")
            return try CaptureDateResolver().resolve(document:.init(tags:["Filename:CaptureDate":.string(raw)]),snapshot:snapshot,policy:policy)
        case .referenceFile(let field):
            let matched=try await matchReference(snapshot:snapshot,context:context)
            switch field {
            case .creation:return CaptureDateResolver.instant(matched.creationDate,source:"Reference file creation: "+matched.url.lastPathComponent)
            case .modification:return CaptureDateResolver.instant(matched.modificationDate,source:"Reference file modification: "+matched.url.lastPathComponent)
            case .capture:
                guard let reader=context.reader else { throw RestoreError(.runtimeUnavailable,"A metadata reader is required for reference capture dates.") }
                var policy=context.datePolicy;policy.source = .automaticCapture
                return try CaptureDateResolver().resolve(document:await reader.read(snapshot:matched),snapshot:matched,policy:policy)
            }
        case .spotlight(let key):
            guard ["kMDItemContentCreationDate","kMDItemContentModificationDate","kMDItemDateAdded","kMDItemDownloadedDate"].contains(key) else { throw RestoreError(.invalidInput,"Unsupported Spotlight date key.") }
            guard let item=NSMetadataItem(url:snapshot.url) else { throw RestoreError(.missingMetadata,"No existing Spotlight record is available.") }
            let value=item.value(forAttribute:key)
            if let date=value as? Date { return CaptureDateResolver.instant(date,source:key) }
            if let dates=value as? [Date],let latest=dates.max() { return CaptureDateResolver.instant(latest,source:key,warnings:dates.count>1 ? ["Latest of \(dates.count) existing Spotlight date records."]:[]) }
            throw RestoreError(.missingMetadata,"The selected Spotlight date is unavailable; indexing was not started.")
        case .automaticCapture,.tag:
            let document:MetadataDocument
            if let cached=context.metadata { document=cached }
            else if let reader=context.reader { document=try await reader.read(snapshot:snapshot) }
            else { throw RestoreError(.runtimeUnavailable,"A metadata reader is required.") }
            var policy=context.datePolicy;policy.source=source
            return try CaptureDateResolver().resolve(document:document,snapshot:snapshot,policy:policy)
        }
    }
    private func matchReference(snapshot:FileSnapshot,context:ReferenceDateContext) async throws -> FileSnapshot {
        guard let input=context.inputRoot?.standardizedFileURL,let reference=context.referenceRoot?.standardizedFileURL else { throw RestoreError(.invalidInput,"Choose input and reference folder roots.") }
        let path=snapshot.url.standardizedFileURL.path,prefix=input.path+"/"
        guard path.hasPrefix(prefix) else { throw RestoreError(.invalidInput,"Source is outside the selected input root.") }
        let exact=reference.appendingPathComponent(String(path.dropFirst(prefix.count)))
        if FileManager.default.fileExists(atPath:exact.path) {
            let candidate=try FileIdentityReader().snapshot(at:exact)
            guard candidate.kind == .regular else { throw RestoreError(.unsupported,"The matching reference is not an available ordinary file.") };return candidate
        }
        guard context.allowBasenameFallback else { throw RestoreError(.missingMetadata,"No reference file matches the relative path.") }
        var options=DiscoveryOptions();options.recursive=true;options.includeFolders=false
        let result=await SourceInventory().scan(urls:[reference],options:options)
        let matches=result.snapshots.filter {$0.url.lastPathComponent==snapshot.url.lastPathComponent}
        guard matches.count==1,let match=matches.first else { throw RestoreError(matches.isEmpty ? .missingMetadata:.conflict,"Reference basename matching must produce exactly one file.") }
        return match
    }
}
