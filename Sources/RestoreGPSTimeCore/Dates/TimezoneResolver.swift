import Foundation

public struct TimezoneResolver {
    public init() {}
    public func resolve(_ wall:WallClock,policy:DatePolicy,quickTimeInteger:Bool) throws -> (instant:Date,offset:Int,interpretation:String) {
        let naive=try WallClockParser().utcBase(wall)
        if let offset=wall.explicitOffset { return (naive.addingTimeInterval(-Double(offset)+wall.fraction),offset,"Explicit UTC offset") }
        if quickTimeInteger && policy.quickTime == nil { throw RestoreError(.timezoneRequired,"Choose whether QuickTime integer dates mean UTC or local camera time.") }
        if quickTimeInteger && policy.quickTime == .utc { return (naive.addingTimeInterval(wall.fraction),0,"QuickTime integer date interpreted as UTC") }
        let zone:TimeZone
        if let offset=policy.fixedOffsetSeconds {
            guard (-64800...64800).contains(offset),let fixed=TimeZone(secondsFromGMT:offset) else { throw RestoreError(.invalidInput,"Invalid selected fixed UTC offset.") }
            zone=fixed
        } else if let id=policy.timeZoneID {
            guard let selected=TimeZone(identifier:id) else { throw RestoreError(.invalidInput,"Unknown timezone: \(id)") };zone=selected
        } else { throw RestoreError(.timezoneRequired,"This date has no UTC offset. Select its camera timezone.") }
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let offsets=Set((-48...48).map {zone.secondsFromGMT(for:naive.addingTimeInterval(Double($0)*3600))})
        let candidates=offsets.map { (naive.addingTimeInterval(-Double($0)),$0) }.filter { WallClockParser.matches(wall,calendar:calendar,date:$0.0) }.sorted {$0.0<$1.0}
        guard !candidates.isEmpty else { throw RestoreError(.nonexistentTime,"This clock time does not exist in \(zone.identifier) because of a timezone transition.") }
        if candidates.count>1 && policy.dstChoice==nil { throw RestoreError(.ambiguousTime,"This clock time occurs twice in \(zone.identifier). Choose the earlier or later occurrence.") }
        let chosen=policy.dstChoice == .later ? candidates.last! : candidates.first!
        let note=candidates.count>1 ? " (\(policy.dstChoice!.rawValue) occurrence)":""
        return (chosen.0.addingTimeInterval(wall.fraction),chosen.1,zone.identifier+note)
    }
}
