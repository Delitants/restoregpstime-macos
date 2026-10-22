import Foundation

public struct RestoreError: Error, LocalizedError, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case runtimeUnavailable, invalidInput, processFailed, outputLimit, timeout, cancelled
        case malformedMetadata, unsupported, timezoneRequired, ambiguousTime, nonexistentTime
        case missingMetadata, conflict, io, verificationFailed, recoveryNeeded
    }
    public let code: Code
    public let detail: String
    public init(_ code: Code, _ detail: String) { self.code = code; self.detail = detail }
    public var errorDescription: String? { detail }
}
