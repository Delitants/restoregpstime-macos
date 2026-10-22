import Foundation

public struct MetadataDecoder {
    public init() {}
    public func decode(_ data: Data) throws -> MetadataDocument {
        let json:Any
        do { json=try JSONSerialization.jsonObject(with:data) } catch { throw RestoreError(.malformedMetadata,"Metadata helper returned invalid JSON.") }
        guard let records=json as? [[String:Any]],records.count==1,let record=records.first else { throw RestoreError(.malformedMetadata,"Expected metadata for exactly one file.") }
        let registry=TagRegistry()
        var grouped=[String:[MetadataOccurrence]]()
        for raw in record.keys.sorted() {
            let canonical=MetadataDocument.canonicalID(raw)
            var value=TagValue.fromJSON(record[raw]!)
            if registry.tags[canonical]=="list" {if case .array=value {} else {value = .array([.string(value.text)])}}
            grouped[canonical,default:[]].append(.init(rawID:raw,qualifiedID:canonical,value:value))
        }
        var tags=[String:TagValue](),evidence=[String:[MetadataOccurrence]]()
        for (id,values) in grouped {
            if let first=values.first,values.allSatisfy({$0.value==first.value}) {tags[id]=first.value}
            if values.count>1 || values.contains(where:{$0.rawID != id}) {evidence[id]=values}
        }
        let detected=(tags["File:FileType"] ?? tags["FileType"])?.text.uppercased() ?? "UNKNOWN"
        let type=["WEBP (LOSSLESS)","EXTENDED WEBP","EXTENDED WEBP (LOSSLESS)"].contains(detected) ? "WEBP":detected
        let photos:Set<String>=["JPEG","TIFF","HEIC","HEIF","PNG","WEBP","AVIF","GIF"]
        let raw:Set<String>=["DNG","CR2","CR3","NEF","ARW","RAF","ORF","RW2","PEF","RAW"]
        let videos:Set<String>=["MOV","MP4","M4V","3GP","3G2","AVI","MKV","WEBM","M2TS"]
        let family:ContainerFamily = photos.contains(type) ? .photo : (raw.contains(type) ? .raw : (videos.contains(type) ? .video : .unknown))
        let diagnostics=grouped.keys.sorted().filter {$0.hasSuffix(":Warning") || $0.hasSuffix(":Error")}.flatMap {grouped[$0]!.map {$0.value.text}}
        return .init(tags:tags,profile:.init(identifier:type,family:family),diagnostics:diagnostics,copyEvidence:evidence.isEmpty ? nil:evidence)
    }
}
