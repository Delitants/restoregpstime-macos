import Foundation

public enum BackupMode:String,Codable,Sendable {case metadata,full,none}
public enum SaveMode:String,Codable,Sendable {case saveCopies,modifyInPlace}
public enum MetadataDestination:String,Codable,Sendable {case embedded,xmpSidecar}
public enum FinderMutation:Codable,Equatable,Sendable {
    case extensionHidden(Bool),locked(Bool),label(Int),creator(Data),fileType(Data),removeWhereFroms,notify
}
public struct OperationRequest:Codable,Equatable,Sendable {
    public var isFinderNotificationOnly:Bool {dates==nil && location==nil && tags.isEmpty && !removeGPS && !stripMetadata && rename.preserveOriginal && !trashHiddenFiles && !finder.isEmpty && finder.allSatisfy {$0 == .notify}}
    public var dates:DatePolicy?
    public var location:LocationWriteOptions?
    public var placeQuery:PlaceQueryDefaults?
    public var tags=[TagMutation]()
    public var removeGPS=false
    public var stripMetadata=false
    public var metadataDestination:MetadataDestination = .embedded
    public var rename:NameTemplate = .original
    public var finder=[FinderMutation]()
    public var trashHiddenFiles=false
    public var excludedSourceKeys=Set<String>()
    public var groups=GroupOverrides()
    public var placeOverrides=[String:PlaceMatch]()
    public init() {}
}
public struct BatchOptions:Codable,Equatable,Sendable {
    public var mode:SaveMode = .saveCopies
    public var backupMode:BackupMode?
    public var effectiveBackupMode:BackupMode {backupMode ?? .full}
    public var outputRoot:URL?
    public var recoveryRoot:URL?
    public var importRoots=[URL]()
    public var referenceRoot:URL?
    public var allowReferenceBasenameFallback=false
    public init() {}
}
