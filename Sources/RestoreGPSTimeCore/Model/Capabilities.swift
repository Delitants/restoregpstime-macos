import Foundation

public enum OperationKind: String, Codable, CaseIterable, Sendable { case filesystemDates, rename, embeddedWrite, removeGPS, stripMetadata, finderAttributes }
public enum ContainerFamily: String, Codable, Sendable { case photo, raw, video, unknown }
public struct ContainerProfile: Codable, Equatable, Sendable {
    public let identifier: String
    public let family: ContainerFamily
    public init(identifier: String, family: ContainerFamily) { self.identifier = identifier; self.family = family }
}
public struct CapabilityDecision: Codable, Equatable, Sendable {
    public let isSupported: Bool
    public let reason: String
    public init(_ supported: Bool, _ reason: String = "") { isSupported = supported; self.reason = reason }
}
