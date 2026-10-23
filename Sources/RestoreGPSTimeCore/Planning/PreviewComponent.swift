import Foundation

public enum PreviewComponent:String,CaseIterable,Codable,Sendable {
    case dates,places,metadata,finder
    public var title:String {switch self {case .dates:return "Dates & time";case .places:return "Location names";case .metadata:return "Metadata";case .finder:return "Finder attributes"}}
    public func isSelected(in value:OperationRequest)->Bool {
        switch self {
        case .dates:return value.dates != nil
        case .places:return value.location != nil || !value.rename.preserveOriginal
        case .metadata:return !value.tags.isEmpty || value.removeGPS || value.stripMetadata
        case .finder:return !value.finder.isEmpty
        }
    }
    public func request(from value:OperationRequest)->OperationRequest {
        var scoped=OperationRequest();scoped.excludedSourceKeys=value.excludedSourceKeys;scoped.groups=value.groups
        switch self {
        case .dates:scoped.dates=value.dates;scoped.metadataDestination=value.metadataDestination
        case .places:scoped.location=value.location;scoped.rename=value.rename;scoped.placeQuery=value.placeQuery ?? PlaceQueryDefaults();scoped.placeOverrides=value.placeOverrides;scoped.metadataDestination=value.metadataDestination
        case .metadata:scoped.tags=value.tags;scoped.removeGPS=value.removeGPS;scoped.stripMetadata=value.stripMetadata;scoped.metadataDestination=value.metadataDestination
        case .finder:scoped.finder=value.finder
        }
        return scoped
    }
}
