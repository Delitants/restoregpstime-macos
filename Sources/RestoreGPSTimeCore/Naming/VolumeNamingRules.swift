import Foundation
import Darwin

public struct VolumeNamingRules:Codable,Equatable,Sendable {
    public let caseSensitive:Bool
    public let maxNameBytes:Int
    public init(caseSensitive:Bool=false,maxNameBytes:Int=255) { self.caseSensitive=caseSensitive;self.maxNameBytes=maxNameBytes }
    public func collisionKey(_ path:String)->String {
        let normalized=path.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.folding(options:.caseInsensitive,locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping
    }
    public static func detect(at directory:URL) throws -> VolumeNamingRules {
        let values=try directory.resourceValues(forKeys:[.volumeSupportsCaseSensitiveNamesKey])
        let limit=pathconf(directory.path,_PC_NAME_MAX)
        return .init(caseSensitive:values.volumeSupportsCaseSensitiveNames ?? false,maxNameBytes:limit>0 ? Int(limit):255)
    }
}
