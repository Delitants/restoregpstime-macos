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
        var notes=[String]()
        if policy.requiresMonotonicFileDates && (creation ?? snapshot.creationDate) > (modification ?? snapshot.modificationDate) {
            guard policy.normalizeCompanionDate else { throw RestoreError(.conflict,"The volume requires changing the unselected companion date; choose normalization or another date.") }
            if creation != nil { modification=creation;notes.append("Modification date normalized to creation date.") }
            else { creation=modification;notes.append("Creation date normalized to modification date.") }
        }
        return .init(creationDate:creation,modificationDate:modification,embeddedDate:policy.targets.contains(.capture) && !policy.removeEmbeddedDates ? final:nil,embeddedOffsetSeconds:resolution.offsetSeconds,removeEmbeddedDates:policy.removeEmbeddedDates,notes:notes)
    }
}
