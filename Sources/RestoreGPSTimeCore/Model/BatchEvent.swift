import Foundation

public enum GroupStatus:String,Codable,Sendable {case committed,blocked,excluded,failed,cancelled,recoveryNeeded,restored}
public struct GroupResult:Codable,Equatable,Sendable {
    public let groupID:UUID
    public let status:GroupStatus
    public let outputs:[URL]
    public let errors:[String]
    public let recoveryURL:URL?
    public init(groupID:UUID,status:GroupStatus,outputs:[URL]=[],errors:[String]=[],recoveryURL:URL?=nil) {self.groupID=groupID;self.status=status;self.outputs=outputs;self.errors=errors;self.recoveryURL=recoveryURL}
}
public struct BatchReport:Codable,Equatable,Sendable {
    public let schema:Int
    public let batchID:UUID
    public let startedAt:Date,finishedAt:Date
    public let plan:BatchPlan
    public let results:[GroupResult]
    public let cancelled:Bool
    public var success:Bool {!cancelled && results.allSatisfy {$0.status == .committed || $0.status == .excluded}}
    public init(plan:BatchPlan,startedAt:Date,results:[GroupResult],cancelled:Bool) {schema=1;batchID=plan.id;self.startedAt=startedAt;finishedAt=Date();self.plan=plan;self.results=results;self.cancelled=cancelled}
}
public enum BatchEvent:Sendable {
    case started(UUID,totalGroups:Int)
    case progress(UUID,phase:String)
    case rejected(PlanValidationResult)
    case group(GroupResult)
    case finished(BatchReport)
}
