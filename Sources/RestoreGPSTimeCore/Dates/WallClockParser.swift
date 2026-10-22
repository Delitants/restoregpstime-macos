import Foundation

public struct WallClockParser {
    public init() {}
    public func parse(_ raw:String) throws -> WallClock {
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let regex=try NSRegularExpression(pattern:#"^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(?:\s*(Z|[+-]\d{2}:?\d{2}))?$"#)
        guard let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { throw RestoreError(.invalidInput,"Invalid date: \(text)") }
        func part(_ i:Int)->String { guard let r=Range(match.range(at:i),in:text) else {return ""};return String(text[r]) }
        let fraction=part(7),offset=part(8)
        let value=WallClock(year:Int(part(1))!,month:Int(part(2))!,day:Int(part(3))!,hour:Int(part(4))!,minute:Int(part(5))!,second:Int(part(6))!,fraction:Double("0."+fraction) ?? 0,fractionalPrecision:fraction.count,explicitOffset:offset.isEmpty ? nil : try parseOffset(offset))
        _=try utcBase(value)
        return value
    }
    public func parseOffset(_ value:String) throws -> Int {
        if value=="Z" { return 0 }
        let regex=try NSRegularExpression(pattern:#"^([+-])(\d{2}):?(\d{2})$"#)
        guard let m=regex.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),
              let hr=Range(m.range(at:2),in:value),let mr=Range(m.range(at:3),in:value),let hour=Int(value[hr]),let minute=Int(value[mr]),minute<60,hour<=18,hour<18 || minute==0 else { throw RestoreError(.invalidInput,"Invalid UTC offset: \(value)") }
        return (value.hasPrefix("-") ? -1:1)*(hour*3600+minute*60)
    }
    func utcBase(_ value:WallClock) throws -> Date {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let c=DateComponents(year:value.year,month:value.month,day:value.day,hour:value.hour,minute:value.minute,second:value.second)
        guard (1...9999).contains(value.year), let date=calendar.date(from:c), Self.matches(value,calendar:calendar,date:date) else { throw RestoreError(.invalidInput,"The date has invalid calendar components.") }
        return date
    }
    static func matches(_ value:WallClock,calendar:Calendar,date:Date)->Bool {
        let c=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date)
        return c.year==value.year && c.month==value.month && c.day==value.day && c.hour==value.hour && c.minute==value.minute && c.second==value.second
    }
}
