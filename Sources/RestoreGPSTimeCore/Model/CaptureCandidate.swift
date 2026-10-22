import Foundation

public struct CaptureCandidate:Codable,Equatable,Sendable {
    public let tag:String
    public let original:String
    public let quickTimeInteger:Bool
}
public struct WallClock:Equatable,Sendable {
    public let year:Int,month:Int,day:Int,hour:Int,minute:Int,second:Int
    public let fraction:Double
    public let fractionalPrecision:Int
    public let explicitOffset:Int?
    public let nanoseconds:Int32?
    init(year:Int,month:Int,day:Int,hour:Int,minute:Int,second:Int,fraction:Double,fractionalPrecision:Int,explicitOffset:Int?,nanoseconds:Int32?=nil) {
        self.year=year;self.month=month;self.day=day;self.hour=hour;self.minute=minute;self.second=second;self.fraction=fraction;self.fractionalPrecision=fractionalPrecision;self.explicitOffset=explicitOffset;self.nanoseconds=nanoseconds
    }
}
