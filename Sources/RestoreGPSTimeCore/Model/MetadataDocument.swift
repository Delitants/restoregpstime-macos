import Foundation

public struct MetadataOccurrence:Codable,Equatable,Sendable {
    public let rawID:String,qualifiedID:String,value:TagValue
    public init(rawID:String,qualifiedID:String,value:TagValue) {self.rawID=rawID;self.qualifiedID=qualifiedID;self.value=value}
    public var selectableID:String {
        guard rawID==qualifiedID else {return rawID}
        var parts=rawID.split(separator:":").map(String.init)
        guard parts.count>=2 else {return rawID};parts.insert("Copy0",at:1);return parts.joined(separator:":")
    }
}
public struct MetadataDocument:Codable,Equatable,Sendable {
    public let tags:[String:TagValue]
    public let profile:ContainerProfile
    public let diagnostics:[String]
    // Only aliased/repeated fields need extra evidence; ordinary canonical fields
    // already retain their original identifier and value in tags.
    public let copyEvidence:[String:[MetadataOccurrence]]?
    public init(tags:[String:TagValue],profile:ContainerProfile = .init(identifier:"UNKNOWN",family:.unknown),diagnostics:[String]=[],copyEvidence:[String:[MetadataOccurrence]]?=nil) {
        self.tags=tags;self.profile=profile;self.diagnostics=diagnostics;self.copyEvidence=copyEvidence
    }
    public var ambiguousIdentifiers:Set<String> {Set((copyEvidence ?? [:]).filter {_,values in guard let first=values.first else {return false};return values.contains {$0.value != first.value}}.keys)}
    public var repeatedIdentifiers:Set<String> {Set((copyEvidence ?? [:]).filter {$0.value.count>1}.keys)}
    public var occurrences:[MetadataOccurrence] {(copyEvidence ?? [:]).keys.sorted().flatMap {copyEvidence?[$0] ?? []}}
    public func values(for id:String)->[TagValue] {if let evidence=copyEvidence?[id] {return evidence.map(\.value)};return tags[id].map {[$0]} ?? []}
    public func readValue(_ id:String) throws -> TagValue? {
        let canonical=Self.canonicalID(id)
        if canonical != id {
            if let evidence=copyEvidence?[canonical] {return evidence.first {$0.rawID==id || $0.selectableID==id}?.value}
            let copies=id.split(separator:":").dropFirst().dropLast().filter {$0.range(of:#"^Copy\d+$"#,options:.regularExpression) != nil}
            guard copies.count==1 else {throw RestoreError(.invalidInput,"Select one metadata copy identifier.")}
            return copies.first=="Copy0" ? tags[canonical]:nil
        }
        if ambiguousIdentifiers.contains(id) {throw RestoreError(.conflict,"Conflicting metadata copies exist for "+id+". Select a specific copy or an explicit date/place correction.")}
        return tags[id]
    }
    public func requireQualifiedLayout() throws {
        let repeated=repeatedIdentifiers.filter {!qualifiedRepeatedField($0)}.sorted()
        guard repeated.isEmpty else {throw RestoreError(.unsupported,"Repeated metadata fields require separate write qualification: "+repeated.prefix(8).joined(separator:", ")+". File dates, copies and explicit sidecars remain available when their selected sources are unambiguous.")}
    }
    func qualifiedRepeatedField(_ id:String)->Bool {
        if profile.family == .photo,["HEIC","HEIF"].contains(profile.identifier),[
            "QuickTime:HEVCConfigurationVersion","QuickTime:GeneralProfileSpace",
            "QuickTime:GeneralTierFlag","QuickTime:GeneralProfileIDC",
            "QuickTime:GenProfileCompatibilityFlags","QuickTime:ConstraintIndicatorFlags",
            "QuickTime:GeneralLevelIDC","QuickTime:MinSpatialSegmentationIDC",
            "QuickTime:ParallelismType","QuickTime:ChromaFormat","QuickTime:BitDepthLuma",
            "QuickTime:BitDepthChroma","QuickTime:AverageFrameRate","QuickTime:ConstantFrameRate",
            "QuickTime:NumTemporalLayers","QuickTime:TemporalIDNested"
        ].contains(id) {
            // Exact read-only hvcC observations from ExifTool's HEVCConfig table.
            // Different image items may have different codec values. The complete
            // occurrence multiset still must survive verifyDiff, and heif-items-v1
            // protects every codec property, media extent and item association.
            // This does not qualify HDR/auxiliary layouts or editable metadata.
            return true
        }
        if profile.family == .video {
            if id=="QuickTime:HandlerType" {return !values(for:id).isEmpty && values(for:id).allSatisfy {["mdir","mdta"].contains($0.text)}}
            // MOV has distinct media/data handlers within one track. Their complete
            // value multisets are protected separately by metadata diff + media hashes.
            if id.range(of:#"^Track\d+:Handler(Class|Type|VendorID|Description)$"#,options:.regularExpression) != nil {return true}
        }
        if profile.identifier=="WEBP",["RIFF:ImageWidth","RIFF:ImageHeight"].contains(id),let first=values(for:id).first {return values(for:id).allSatisfy {$0==first}}
        return false
    }
    static func sameValues(_ a:[TagValue],_ b:[TagValue]) throws -> Bool {
        if a==b {return true};guard a.count==b.count else {return false}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var counts=[Data:Int]()
        for value in a {counts[try encoder.encode(value),default:0]+=1}
        for value in b {let key=try encoder.encode(value);guard let count=counts[key],count>0 else {return false};counts[key]=count-1}
        return true
    }
    static func canonicalID(_ raw:String)->String {
        let parts=raw.split(separator:":").map(String.init)
        guard parts.count>=3 else {return raw}
        return parts.enumerated().filter {index,value in index==0 || index==parts.count-1 || value.range(of:#"^Copy\d+$"#,options:.regularExpression)==nil}.map(\.element).joined(separator:":")
    }
    public func value(_ ids:String...)->TagValue? {ids.lazy.compactMap {tags[$0]}.first}
}
