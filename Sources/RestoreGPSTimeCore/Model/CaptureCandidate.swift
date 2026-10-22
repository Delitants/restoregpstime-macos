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
}
