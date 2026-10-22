import Foundation

public actor MetadataReader {
    private let paths: RuntimePaths
    private let limiter=HelperLimiter.shared
    private var active=0,peak=0,completed=0
    public init(paths: RuntimePaths) { self.paths = paths }
    public func metrics() -> MetadataReadMetrics { .init(active:active,maximumActive:peak,completed:completed) }
    public func read(snapshot: FileSnapshot) async throws -> MetadataDocument {
        guard snapshot.kind == .regular else { return .init(tags:[:]) }
        await limiter.acquire()
        active+=1;peak=max(peak,active)
        let outcome:Result<MetadataDocument,Error>
        do {
            if Task.isCancelled { throw RestoreError(.cancelled,"Metadata inspection cancelled.") }
            let args=["-j","-G1","-a","-s","-n","-struct","-charset","filename=UTF8","-api","LargeFileSupport=1","--",snapshot.url.path]
            let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(args),environment:paths.environment,timeout:60)
            let document=try MetadataDecoder().decode(result.stdout)
            if result.exitStatus != 0 && document.diagnostics.isEmpty { throw RestoreError(.processFailed,String(decoding:result.stderr,as:UTF8.self)) }
            outcome = .success(document)
        } catch { outcome = .failure(error) }
        active-=1;completed+=1
        await limiter.release()
        return try outcome.get()
    }
}

public struct MetadataReadMetrics:Sendable { public let active:Int;public let maximumActive:Int;public let completed:Int }

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
