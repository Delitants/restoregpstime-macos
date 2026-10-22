import Foundation
import CoreFoundation

public struct TagID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard rawValue.range(of: "^[A-Za-z][A-Za-z0-9_-]*(?::[A-Za-z0-9_-]+){1,2}$", options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue
    }
}
public enum TagValue: Codable, Equatable, Sendable {
    case string(String), integer(Int64), real(Double), bool(Bool), array([TagValue]), object([String:TagValue]), null
    public var text: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .bool(let value): return value ? "true":"false"
        case .array(let values): return values.map(\.text).joined(separator: "; ")
        case .object(let values): return values.keys.sorted().map { "\($0): \(values[$0]!.text)" }.joined(separator: "; ")
        case .null: return ""
        }
    }
    public var double: Double? {
        switch self { case .real(let n): return n; case .integer(let n): return Double(n); case .string(let s): return Double(s); default: return nil }
    }
    static func fromJSON(_ value: Any) -> TagValue {
        switch value {
        case let string as String: return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if String(cString:number.objCType).contains("f") || String(cString:number.objCType).contains("d") { return .real(number.doubleValue) }
            return .integer(number.int64Value)
        case let array as [Any]: return .array(array.map(fromJSON))
        case let object as [String:Any]: return .object(object.mapValues(fromJSON))
        default: return .null
        }
    }
}
public enum TagMutation: Codable, Equatable, Sendable {
    case set(TagID,TagValue), remove(TagID)
}
