import Foundation

public struct DateMutationPlanner {
    public init() {}
    public func plan(resolution:DateResolution,policy:DatePolicy,snapshot:FileSnapshot,sequenceIndex:Int) throws -> DateMutation {
        guard sequenceIndex>=0,policy.shiftSeconds.isFinite,policy.sequenceStepSeconds.isFinite,policy.targets.rawValue>0,policy.targets.rawValue & ~7 == 0 else { throw RestoreError(.invalidInput,"Invalid date targets or sequence settings.") }
        let base=policy.sequenceStart.map {$0.addingTimeInterval(Double(sequenceIndex)*policy.sequenceStepSeconds)} ?? resolution.instant
        let final=base.addingTimeInterval(policy.shiftSeconds)
        guard final.timeIntervalSince1970.isFinite else { throw RestoreError(.invalidInput,"The adjusted date is out of range.") }
        var creation=policy.targets.contains(.creation) ? final:nil
        var modification=policy.targets.contains(.modification) ? final:nil
        if policy.shiftOriginalTargets {
            guard policy.sequenceStart==nil else {throw RestoreError(.invalidInput,"Independent original-date shifts cannot also use a date sequence.")}
            if creation != nil {creation=snapshot.creationDate.addingTimeInterval(policy.shiftSeconds)}
            if modification != nil {modification=snapshot.modificationDate.addingTimeInterval(policy.shiftSeconds)}
        }
        var notes=[String]()
        if policy.requiresMonotonicFileDates && (creation ?? snapshot.creationDate) > (modification ?? snapshot.modificationDate) {
            guard policy.normalizeCompanionDate else { throw RestoreError(.conflict,"The volume requires changing the unselected companion date; choose normalization or another date.") }
            if creation != nil { modification=creation;notes.append("Modification date normalized to creation date.") }
            else { creation=modification;notes.append("Creation date normalized to modification date.") }
        }
        var embeddedOffset=resolution.offsetSeconds
        if policy.targets.contains(.capture) && !policy.removeEmbeddedDates {
            let absoluteSource:Bool
            switch policy.source {case .automaticCapture,.tag,.filename,.referenceFile(.capture):absoluteSource=false;default:absoluteSource=true}
            if absoluteSource {
                if let offset=policy.fixedOffsetSeconds {
                    guard (-64800...64800).contains(offset) else {throw RestoreError(.invalidInput,"The selected output offset is out of range.")}
                    embeddedOffset=offset
                } else if let identifier=policy.timeZoneID {
                    guard let zone=TimeZone(identifier:identifier) else {throw RestoreError(.invalidInput,"Unknown output timezone.")}
                    embeddedOffset=zone.secondsFromGMT(for:final)
                }
            }
        }
        let precision=max(resolution.fractionalPrecision,CaptureDateResolver.fractionalPrecision(final.timeIntervalSince1970))
        return .init(creationDate:creation,modificationDate:modification,embeddedDate:policy.targets.contains(.capture) && !policy.removeEmbeddedDates ? final:nil,embeddedPrecision:precision,embeddedOffsetSeconds:embeddedOffset,removeEmbeddedDates:policy.targets.contains(.capture) && policy.removeEmbeddedDates,notes:notes)
    }
}
