import Foundation

public struct MetadataStripProfiles:Sendable {
    public init() {}
    static let gpsFields=Set(["GPSVersionID","GPSLatitudeRef","GPSLatitude","GPSLongitudeRef","GPSLongitude","GPSAltitudeRef","GPSAltitude","GPSTimeStamp","GPSSatellites","GPSStatus","GPSMeasureMode","GPSDOP","GPSSpeedRef","GPSSpeed","GPSTrackRef","GPSTrack","GPSImgDirectionRef","GPSImgDirection","GPSMapDatum","GPSDestLatitudeRef","GPSDestLatitude","GPSDestLongitudeRef","GPSDestLongitude","GPSDestBearingRef","GPSDestBearing","GPSDestDistanceRef","GPSDestDistance","GPSProcessingMethod","GPSAreaInformation","GPSDateStamp","GPSDifferential","GPSHPositioningError"])
    static let namedLocationFields=Set(["XMP-photoshop:City","XMP-photoshop:State","XMP-photoshop:Country","XMP-iptcCore:CountryCode","XMP-iptcCore:Location","IPTC:City","IPTC:Province-State","IPTC:Country-PrimaryLocationName","IPTC:Country-PrimaryLocationCode","IPTC:Sub-location","Keys:GPSCoordinates","UserData:GPSCoordinates","ItemList:GPSCoordinates","Keys:LocationName","Keys:LocationBody","Keys:LocationNote","Keys:LocationRole","Keys:LocationDate","Keys:LocationAccuracyHorizontal"])
    static let preservedSelectors=["-ICC_Profile","-MakerNotes","-IFD0:Orientation","-IFD0:XResolution","-IFD0:YResolution","-IFD0:ResolutionUnit","-IFD0:YCbCrPositioning","-ExifIFD:ColorSpace","-ExifIFD:ComponentsConfiguration","-ExifIFD:ExifImageWidth","-ExifIFD:ExifImageHeight","-ExifIFD:Gamma","-InteropIFD:InteropIndex","-InteropIFD:InteropVersion","-ExifIFD:ImageUniqueID","-ExifIFD:RelatedSoundFile","-XMP-tiff:Orientation","-XMP-tiff:XResolution","-XMP-tiff:YResolution","-XMP-tiff:ResolutionUnit","-XMP-xmpMM:DocumentID","-XMP-xmpMM:InstanceID","-XMP-xmpMM:OriginalDocumentID","-XMP-exif:ImageUniqueID","-XMP-apple-fi:ContentIdentifier"]
    static let protectedIDs=Set(preservedSelectors.map {String($0.dropFirst())}.filter {$0.contains(":")})
    static func protectedTag(_ key:String)->Bool {
        if key=="Photoshop:IPTCDigest" {return false}
        if protectedIDs.contains(key) || key.hasPrefix("ICC") {return true}
        let group=key.split(separator:":").first.map(String.init) ?? ""
        let descriptive:Set<String>=["IFD0","ExifIFD","GPS","InteropIFD","IPTC","JPEG","XMP-dc","XMP-exif","XMP-photoshop","XMP-iptcCore","XMP-xmp","XMP-tiff","XMP-xmpMM","XMP-x"]
        return !descriptive.contains(group)
    }
    public func qualifyStrip(document:MetadataDocument) throws {
        let knownXMP:Set<String>=["XMP-dc","XMP-exif","XMP-photoshop","XMP-iptcCore","XMP-xmp","XMP-tiff","XMP-xmpMM","XMP-x"]
        for key in document.tags.keys {
            let group=key.split(separator:":").first.map(String.init) ?? ""
            if group=="IFD1" || (group.hasPrefix("Photoshop") && key != "Photoshop:IPTCDigest") || (group.hasPrefix("XMP-") && !knownXMP.contains(group)) {throw RestoreError(.unsupported,"Stripping this thumbnail/Photoshop/XMP layout requires additional fixture qualification: \(key).")}
            if group=="XMP-xmpMM" && !Self.protectedIDs.contains(key) {throw RestoreError(.unsupported,"This XMP resource-link structure requires separate strip qualification.")}
            if Self.looksLikeLocation(key) && !key.hasPrefix("Composite:") && !Self.removableLocation(key) {throw RestoreError(.incompleteRemoval,"Stripping cannot safely remove recognized location data: \(key).")}
        }
    }
    public func validateStrip(profile:ContainerProfile) throws {
        guard profile.family != .raw,profile.identifier=="JPEG" else {throw RestoreError(.unsupported,"Blanket metadata stripping is disabled for this unqualified profile.")}
    }
    static func removableLocation(_ tag:String)->Bool {
        if namedLocationFields.contains(tag) {return true}
        if tag.hasPrefix("GPS:") {return gpsFields.contains(String(tag.dropFirst(4)))}
        if tag.hasPrefix("XMP-exif:") {return gpsFields.contains(String(tag.dropFirst(9)))}
        return false
    }
    static func looksLikeLocation(_ tag:String)->Bool {
        let lower=tag.lowercased()
        return removableLocation(tag) || lower.contains(":gps") || lower.contains("locationiso6709") || lower.contains("locationinformation") || lower.contains("locationlatitude") || lower.contains("locationlongitude") || lower.hasPrefix("xmp-iptcext:locationshown") || lower.hasPrefix("xmp-iptcext:locationcreated")
    }
    public func locationRemovals(in document:MetadataDocument) throws -> [TagMutation] {
        var result=[TagMutation]()
        for key in document.tags.keys.sorted() where Self.looksLikeLocation(key) {
            if key.hasPrefix("Composite:") {continue}
            guard Self.removableLocation(key),let tag=TagID(rawValue:key) else {throw RestoreError(.incompleteRemoval,"Recognized location data cannot be safely removed by this profile: \(key).")}
            result.append(.remove(tag))
        }
        return result
    }
    public func verifyLocationRemoved(in document:MetadataDocument) throws {
        let remaining=document.tags.keys.filter {Self.looksLikeLocation($0)}.sorted()
        guard remaining.isEmpty else {throw RestoreError(.incompleteRemoval,"Recognized location metadata remains: "+remaining.joined(separator:", "))}
    }
}
