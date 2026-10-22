import Foundation

public struct MetadataDocument: Codable, Equatable, Sendable {
    public let tags: [String:TagValue]
    public let profile: ContainerProfile
    public let diagnostics: [String]
    public init(tags: [String:TagValue], profile: ContainerProfile = .init(identifier:"UNKNOWN",family:.unknown), diagnostics: [String] = []) {
        self.tags = tags; self.profile = profile; self.diagnostics = diagnostics
    }
    public func value(_ ids: String...) -> TagValue? { ids.lazy.compactMap { tags[$0] }.first }
}
