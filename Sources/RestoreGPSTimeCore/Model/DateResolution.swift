import Foundation

public struct DateResolution:Codable,Equatable,Sendable {
    public let source:String
    public let original:String
    public let instant:Date
    public let offsetSeconds:Int
    public let fractionalPrecision:Int
    public let interpretation:String
    public let warnings:[String]
}
