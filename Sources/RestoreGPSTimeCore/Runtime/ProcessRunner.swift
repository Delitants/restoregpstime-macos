import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let exitStatus: Int32
    public let stdout: Data
    public let stderr: Data
    public let duration: TimeInterval
    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

public struct ProcessRunner: Sendable {
    public init() {}
    public func run(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> ProcessResult {
        let state = ChildState()
        return try await withTaskCancellationHandler(operation: {
            if Task.isCancelled { throw RestoreError(.cancelled, "Helper cancelled before launch.") }
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try Self.runBlocking(executable: executable, arguments: arguments, environment: environment, timeout: timeout, state: state)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { state.stop(.cancelled) })
    }

    private static func runBlocking(executable: URL, arguments: [String], environment: [String:String], timeout: TimeInterval, state: ChildState) throws -> ProcessResult {
        let start = Date()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        do { try process.run() } catch { throw RestoreError(.processFailed, "Cannot run \(executable.lastPathComponent): \(error.localizedDescription)") }
        state.started(process.processIdentifier)
        let readers = DispatchGroup()
        for (handle, isError) in [(out.fileHandleForReading, false), (err.fileHandleForReading, true)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { try? handle.close(); readers.leave() }
                do {
                    while let data = try handle.read(upToCount: 65536), !data.isEmpty { state.append(data, isError: isError) }
                } catch { state.stop(.processFailed) }
            }
        }
        let timeoutItem = DispatchWorkItem { state.stop(.timeout) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.01, timeout), execute: timeoutItem)
        process.waitUntilExit()
        state.exited()
        timeoutItem.cancel()
        // Descendants inheriting these pipes cannot keep the caller waiting indefinitely.
        if readers.wait(timeout: .now() + 2) == .timedOut { state.stop(.processFailed) }
        let captured = state.finish()
        if let reason = captured.2 {
            throw RestoreError(reason, "Helper \(reason.rawValue). \(String(decoding: captured.1.prefix(2048), as: UTF8.self))")
        }
        return ProcessResult(exitStatus: process.terminationStatus, stdout: captured.0, stderr: captured.1, duration: Date().timeIntervalSince(start))
    }
}

private final class ChildState: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32 = 0
    private var done = false
    private var reason: RestoreError.Code?
    private var out = Data(), err = Data()
    func started(_ value: Int32) {
        lock.lock(); pid = value; let cancelled = reason != nil; lock.unlock()
        if cancelled { terminate(value) }
    }
    func exited() { lock.lock(); pid = 0; lock.unlock() }
    func append(_ data: Data, isError: Bool) {
        lock.lock()
        let limit = isError ? 1_048_576 : 16_777_216
        let used = isError ? err.count : out.count
        let available = max(0, limit - used)
        if isError { err.append(data.prefix(available)) } else { out.append(data.prefix(available)) }
        let overflow = data.count > available
        lock.unlock()
        if overflow { stop(.outputLimit) }
    }
    func stop(_ code: RestoreError.Code) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        if reason == nil { reason = code }
        let target = pid
        lock.unlock()
        if target > 0 { terminate(target) }
    }
    private func terminate(_ target: Int32) {
        _ = Darwin.kill(target, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
            lock.lock(); let active = !done && pid == target; lock.unlock()
            if active { _ = Darwin.kill(target, SIGKILL) }
        }
    }
    func finish() -> (Data, Data, RestoreError.Code?) {
        lock.lock(); defer { lock.unlock() }
        done = true; pid = 0
        return (out, err, reason)
    }
}
