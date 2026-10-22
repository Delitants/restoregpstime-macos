import Foundation

public struct MetadataDecoder {
    public init() {}
    public func decode(_ data: Data) throws -> MetadataDocument {
        let json:Any
        do { json=try JSONSerialization.jsonObject(with:data) } catch { throw RestoreError(.malformedMetadata,"Metadata helper returned invalid JSON.") }
        guard let records=json as? [[String:Any]],records.count==1,let record=records.first else { throw RestoreError(.malformedMetadata,"Expected metadata for exactly one file.") }
        let tags=record.mapValues(TagValue.fromJSON)
        let type=(tags["File:FileType"] ?? tags["FileType"])?.text.uppercased() ?? "UNKNOWN"
        let photos:Set<String>=["JPEG","TIFF","HEIC","HEIF","PNG","WEBP","AVIF","GIF"]
        let raw:Set<String>=["DNG","CR2","CR3","NEF","ARW","RAF","ORF","RW2","PEF","RAW"]
        let videos:Set<String>=["MOV","MP4","M4V","3GP","3G2","AVI","MKV","WEBM","M2TS"]
        let family:ContainerFamily = photos.contains(type) ? .photo : (raw.contains(type) ? .raw : (videos.contains(type) ? .video : .unknown))
        let diagnostics=tags.filter { $0.key.hasSuffix(":Warning") || $0.key.hasSuffix(":Error") }.sorted {$0.key<$1.key}.map {$0.value.text}
        return .init(tags:tags,profile:.init(identifier:type,family:family),diagnostics:diagnostics)
    }
}
