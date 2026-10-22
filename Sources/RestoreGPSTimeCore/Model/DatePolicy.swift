import Foundation

public enum ReferenceDateField:String,Codable,Sendable { case creation,modification,capture }
public enum SourceChoice:Codable,Equatable,Sendable {
    case automaticCapture,tag(String),fileCreation,fileModification,specific(Date),current,filename(String),referenceFile(ReferenceDateField),spotlight(String),reset
}
public enum DSTChoice:String,Codable,Sendable { case earlier,later }
public enum QuickTimeInterpretation:String,Codable,Sendable { case utc,cameraLocal }
public struct DateTargets:OptionSet,Codable,Equatable,Sendable {
    public let rawValue:Int
    public init(rawValue:Int) { self.rawValue=rawValue }
    public static let creation=Self(rawValue:1),modification=Self(rawValue:2),capture=Self(rawValue:4)
}
public struct DatePolicy:Codable,Equatable,Sendable {
    public var source:SourceChoice = .automaticCapture
    public var timeZoneID:String?
    public var fixedOffsetSeconds:Int?
    public var dstChoice:DSTChoice?
    public var quickTime:QuickTimeInterpretation?
    public var targets:DateTargets = [.creation,.modification]
    public var shiftSeconds:Double=0
    public var sequenceStart:Date?
    public var sequenceStepSeconds:Double=0
    public var removeEmbeddedDates=false
    public var normalizeCompanionDate=false
    public var requiresMonotonicFileDates=false
    public init() {}
}
public struct DateMutation:Codable,Equatable,Sendable {
    public var creationDate:Date?
    public var modificationDate:Date?
    public var embeddedDate:Date?
    public var embeddedPrecision:Int=0
    public var embeddedOffsetSeconds:Int
    public var removeEmbeddedDates:Bool
    public var notes:[String]
}
