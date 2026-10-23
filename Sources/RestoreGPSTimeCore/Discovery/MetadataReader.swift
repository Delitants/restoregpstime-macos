import Foundation

public actor MetadataReader {
    private let paths: RuntimePaths
    private let limiter=HelperLimiter.shared
    private var active=0,peak=0,completed=0,helperLaunches=0
    public init(paths: RuntimePaths) { self.paths = paths }
    public func metrics() -> MetadataReadMetrics { .init(active:active,maximumActive:peak,completed:completed,helperLaunches:helperLaunches) }
    public func read(snapshot: FileSnapshot) async throws -> MetadataDocument {
        guard snapshot.kind == .regular else { return .init(tags:[:]) }
        await limiter.acquire()
        active+=1;peak=max(peak,active)
        let outcome:Result<MetadataDocument,Error>
        do {
            if Task.isCancelled { throw RestoreError(.cancelled,"Metadata inspection cancelled.") }
            let args=["-j","-G1:4","-a","-s","-n","-struct","-charset","filename=UTF8","-api","LargeFileSupport=1","--",snapshot.url.path]
            helperLaunches+=1
            let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(args),environment:paths.environment,timeout:60)
            let document=try MetadataDecoder().decode(result.stdout)
            if result.exitStatus != 0 && document.diagnostics.isEmpty { throw RestoreError(.processFailed,String(decoding:result.stderr,as:UTF8.self)) }
            outcome = .success(document)
        } catch { outcome = .failure(error) }
        active-=1;completed+=1
        await limiter.release()
        return try outcome.get()
    }
    public func readBatch(snapshots:[FileSnapshot]) async throws -> [MetadataDocument] {
        try Task.checkCancellation()
        guard snapshots.count<=32 else {throw RestoreError(.invalidInput,"Metadata batches are limited to 32 files.")}
        let files=snapshots.filter {$0.kind == .regular}
        guard !files.isEmpty else {return snapshots.map {_ in .init(tags:[:])}}
        guard Set(files.map { $0.url.path }).count==files.count else {throw RestoreError(.invalidInput,"Metadata batch contains duplicate paths.")}
        await limiter.acquire()
        active+=1;peak=max(peak,active)
        let outcome:Result<[MetadataDocument],Error>
        do {
            try Task.checkCancellation()
            let args=["-j","-G1:4","-a","-s","-n","-struct","-charset","filename=UTF8","-api","LargeFileSupport=1","--"]+files.map { $0.url.path }
            helperLaunches+=1
            let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(args),environment:paths.environment,timeout:60)
            let documents=try MetadataDecoder().decodeBatch(result.stdout,expectedURLs:files.map(\.url))
            let hasFileError=documents.contains {document in document.tags.contains {key,value in key.hasSuffix(":Error") && !value.text.isEmpty}}
            if result.exitStatus != 0 && !(result.exitStatus==1 && hasFileError) {throw RestoreError(.processFailed,String(decoding:result.stderr,as:UTF8.self))}
            var index=0
            outcome = .success(snapshots.map {snapshot in
                guard snapshot.kind == .regular else {return .init(tags:[:])}
                defer {index+=1};return documents[index]
            })
        } catch {outcome = .failure(error)}
        active-=1;completed+=files.count
        await limiter.release()
        return try outcome.get()
    }
}

public struct MetadataReadMetrics:Sendable { public let active:Int;public let maximumActive:Int;public let completed:Int;public let helperLaunches:Int }

actor HelperLimiter {
    static let shared=HelperLimiter(limit:2)
    private var active=0
    private let limit:Int
    private var waiters=[CheckedContinuation<Void,Never>]()
    init(limit:Int) { self.limit=limit }
    func acquire() async {
        if active<limit { active+=1;return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active-=1 } else { waiters.removeFirst().resume() }
    }
}
