import Foundation

public struct DateMutationPlanner {
    public init() {}
    public func plan(resolution:DateResolution,policy:DatePolicy,snapshot:FileSnapshot,sequenceIndex:Int) throws -> DateMutation {
        guard sequenceIndex>=0,policy.shiftSeconds.isFinite,policy.sequenceStepSeconds.isFinite,policy.targets.rawValue>0,policy.targets.rawValue & ~7 == 0 else {throw RestoreError(.invalidInput,"Invalid date targets or sequence settings.")}
        let base:FileTimestamp
        if let start=policy.sequenceStart {
            let precision=CaptureDateResolver.fractionalPrecision(start.timeIntervalSince1970)
            base=try FileTimestamp(date:start).rounded(precision:precision).adding(seconds:policy.sequenceStepSeconds,multiplier:sequenceIndex)
        } else {base=try resolution.exactTimestamp ?? FileTimestamp(date:resolution.instant).rounded(precision:resolution.fractionalPrecision)}
        let final=try base.adding(seconds:policy.shiftSeconds)
        var creation=policy.targets.contains(.creation) ? final:nil,modification=policy.targets.contains(.modification) ? final:nil
        if policy.shiftOriginalTargets {
            guard policy.sequenceStart==nil else {throw RestoreError(.invalidInput,"Independent original-date shifts cannot also use a date sequence.")}
            if creation != nil {creation=try (snapshot.creationTimestamp ?? FileTimestamp(date:snapshot.creationDate)).adding(seconds:policy.shiftSeconds)}
            if modification != nil {modification=try (snapshot.modificationTimestamp ?? FileTimestamp(date:snapshot.modificationDate)).adding(seconds:policy.shiftSeconds)}
        }
        var notes=[String]()
        let currentCreation=try creation ?? snapshot.creationTimestamp ?? FileTimestamp(date:snapshot.creationDate),currentModification=try modification ?? snapshot.modificationTimestamp ?? FileTimestamp(date:snapshot.modificationDate)
        if policy.requiresMonotonicFileDates && currentCreation>currentModification {
            guard policy.normalizeCompanionDate else {throw RestoreError(.conflict,"The volume requires changing the unselected companion date; choose normalization or another date.")}
            if creation != nil {modification=creation;notes.append("Modification date normalized to creation date.")}
            else {creation=modification;notes.append("Creation date normalized to modification date.")}
        }
        var embeddedOffset=resolution.offsetSeconds
        if policy.targets.contains(.capture) && !policy.removeEmbeddedDates {
            let absoluteSource:Bool
            switch policy.source {case .automaticCapture,.tag,.filename,.referenceFile(.capture):absoluteSource=false;default:absoluteSource=true}
            if absoluteSource {
                if let offset=policy.fixedOffsetSeconds {guard (-64800...64800).contains(offset) else {throw RestoreError(.invalidInput,"The selected output offset is out of range.")};embeddedOffset=offset}
                else if let identifier=policy.timeZoneID {guard let zone=TimeZone(identifier:identifier) else {throw RestoreError(.invalidInput,"Unknown output timezone.")};embeddedOffset=zone.secondsFromGMT(for:Date(timeIntervalSince1970:Double(final.seconds)))}
            }
        }
        let capture=policy.targets.contains(.capture) && !policy.removeEmbeddedDates
        return .init(creationDate:creation?.date,modificationDate:modification?.date,embeddedDate:capture ? final.date:nil,embeddedPrecision:max(resolution.fractionalPrecision,final.fractionalPrecision),embeddedOffsetSeconds:embeddedOffset,removeEmbeddedDates:policy.targets.contains(.capture) && policy.removeEmbeddedDates,notes:notes,creationTimestamp:creation,modificationTimestamp:modification,embeddedTimestamp:capture ? final:nil)
    }
}
