import Foundation

public enum BatchEvent:Sendable {
    case started(UUID,totalGroups:Int)
    case progress(UUID,phase:String)
    case rejected(PlanValidationResult)
    case finished(UUID)
}
