import Foundation

public struct DateResolution:Codable,Equatable,Sendable {
    public let source:String
    public let original:String
    public let instant:Date
    public let offsetSeconds:Int
    public let fractionalPrecision:Int
    public let interpretation:String
    public let warnings:[String]
    public let exactTimestamp:FileTimestamp?
    init(source:String,original:String,instant:Date,offsetSeconds:Int,fractionalPrecision:Int,interpretation:String,warnings:[String],exactTimestamp:FileTimestamp?=nil) {
        self.source=source;self.original=original;self.instant=instant;self.offsetSeconds=offsetSeconds;self.fractionalPrecision=fractionalPrecision;self.interpretation=interpretation;self.warnings=warnings;self.exactTimestamp=exactTimestamp
    }
}
