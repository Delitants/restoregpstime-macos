import Foundation

public struct PreparationProgress:Equatable,Sendable {
    public enum Stage:Sendable {
        case discovering,metadata,places,dependencies,fingerprinting,naming,planning
        public var title:String {
            switch self {
            case .discovering:return "Finding files"
            case .metadata:return "Reading metadata"
            case .places:return "Looking up place names"
            case .dependencies:return "Checking bundled tools"
            case .fingerprinting:return "Checking file contents and dates"
            case .naming:return "Allocating filenames"
            case .planning:return "Planning changes"
            }
        }
    }
    public let stage:Stage
    public let completed:Int
    public let total:Int?
    public init(stage:Stage,completed:Int=0,total:Int?=nil) {
        self.stage=stage;self.total=total.map {max(0,$0)}
        self.completed=max(0,min(completed,total ?? Int.max))
    }
    public var message:String {
        if let total {return "\(stage.title): \(completed) of \(total)"}
        return stage.title+"…"
    }
}
