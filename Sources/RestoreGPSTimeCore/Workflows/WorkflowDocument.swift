import Foundation

public struct WorkflowDocument:Codable,Equatable,Sendable {
    public let schema:Int,name:String,request:OperationRequest
    public init(name:String,request:OperationRequest) {
        schema=1;self.name=name
        var portable=request
        portable.placeOverrides=[:];portable.excludedSourceKeys=[];portable.groups=GroupOverrides()
        self.request=portable
    }
}
