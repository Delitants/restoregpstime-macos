import Foundation
import Darwin

/// Exact filesystem precision. Date remains a display/calendar approximation.
public struct FileTimestamp:Codable,Equatable,Comparable,Sendable {
    public let seconds:Int64,nanoseconds:Int32
    public init(seconds:Int64,nanoseconds:Int32) throws {
        guard (0..<1_000_000_000).contains(nanoseconds) else {throw RestoreError(.invalidInput,"Invalid timestamp nanoseconds.")}
        self.seconds=seconds;self.nanoseconds=nanoseconds
    }
    init(_ value:timespec) {seconds=Int64(value.tv_sec);nanoseconds=Int32(value.tv_nsec)}
    init(date:Date) throws {
        let whole=floor(date.timeIntervalSince1970)
        guard whole.isFinite,whole>=Double(Int64.min),whole<Double(Int64.max) else {throw RestoreError(.unsupported,"The selected date exceeds the filesystem timestamp range.")}
        let fraction=Int64(((date.timeIntervalSince1970-whole)*1e9).rounded())
        let carry=fraction==1_000_000_000 ? Int64(1):0,value=Int64(whole).addingReportingOverflow(carry)
        guard !value.overflow else {throw RestoreError(.unsupported,"Timestamp overflow.")}
        seconds=value.partialValue;nanoseconds=Int32(carry==1 ? 0:fraction)
    }
    public static func <(a:Self,b:Self)->Bool {a.seconds==b.seconds ? a.nanoseconds<b.nanoseconds:a.seconds<b.seconds}
    public func adding(seconds interval:Double,multiplier:Int=1) throws -> FileTimestamp {
        guard interval.isFinite,var amount=Decimal(string:String(interval),locale:Locale(identifier:"en_US_POSIX")),!amount.isNaN else {throw RestoreError(.invalidInput,"Invalid date interval.")}
        var rounded=Decimal();NSDecimalRound(&rounded,&amount,9,.plain)
        guard rounded==amount else {throw RestoreError(.unsupported,"Date shifts and sequence steps must be representable in whole nanoseconds.")}
        var count=Decimal(multiplier),delta=Decimal()
        guard NSDecimalMultiply(&delta,&amount,&count,.plain) == .noError else {throw RestoreError(.unsupported,"Date sequence overflow.")}
        var base=NSDecimalNumber(value:seconds).decimalValue+Decimal(Int(nanoseconds))/Decimal(1_000_000_000),result=Decimal()
        guard NSDecimalAdd(&result,&base,&delta,.plain) == .noError else {throw RestoreError(.unsupported,"Adjusted date overflow.")}
        var whole=Decimal();NSDecimalRound(&whole,&result,0,.down)
        guard whole>=NSDecimalNumber(value:Int64.min).decimalValue,whole<=NSDecimalNumber(value:Int64.max).decimalValue else {throw RestoreError(.unsupported,"The adjusted date exceeds the filesystem timestamp range.")}
        let fraction=(result-whole)*Decimal(1_000_000_000)
        return try .init(seconds:NSDecimalNumber(decimal:whole).int64Value,nanoseconds:NSDecimalNumber(decimal:fraction).int32Value)
    }
    public func rounded(precision:Int) throws -> FileTimestamp {
        guard (0...9).contains(precision) else {throw RestoreError(.invalidInput,"Invalid decimal timestamp precision.")}
        let step=Int64(pow(10,Double(9-precision))),fraction=((Int64(nanoseconds)+step/2)/step)*step
        if fraction==1_000_000_000 {
            let value=seconds.addingReportingOverflow(1);guard !value.overflow else {throw RestoreError(.unsupported,"Rounded timestamp overflow.")}
            return try .init(seconds:value.partialValue,nanoseconds:0)
        }
        return try .init(seconds:seconds,nanoseconds:Int32(fraction))
    }
    public var fractionalPrecision:Int {
        guard nanoseconds != 0 else {return 0}
        var value=nanoseconds,digits=9
        while value%10==0 {digits-=1;value/=10}
        return digits
    }
    public var date:Date {Date(timeIntervalSince1970:Double(seconds)+Double(nanoseconds)/1e9)}
    var timeSpec:timespec {timespec(tv_sec:Int(seconds),tv_nsec:Int(nanoseconds))}
    public init(from decoder:Decoder) throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(seconds:container.decode(Int64.self,forKey:.seconds),nanoseconds:container.decode(Int32.self,forKey:.nanoseconds))
    }
    static func matches(_ actual:FileTimestamp?,_ expected:FileTimestamp?,date:Date,expectedDate:Date)->Bool {
        if let expected {return actual==expected}
        return date==expectedDate // Earlier local journals have Date-only evidence.
    }
}
