import Foundation

public struct MediaIntegritySignature:Codable,Equatable,Sendable {
    public let profile:String,validator:String,payloadHash:String,structureHash:String
    public init(profile:String,validator:String,payloadHash:String,structureHash:String) {self.profile=profile;self.validator=validator;self.payloadHash=payloadHash;self.structureHash=structureHash}
}
public struct MediaIntegrityValidator:Sendable {
    public init() {}
    public func signature(at url:URL,profile:ContainerProfile) async throws -> MediaIntegritySignature {
        let worker=Task.detached(priority:.userInitiated) {() async throws -> MediaIntegritySignature in
            let reader=try BoundedMediaReader(url)
            switch profile.identifier {
            case "XMP":return try XMPIntegrity().signature(reader)
            case "MOV","MP4","M4V","3GP":return try await VideoIntegrity().signature(at:url,profile:profile.identifier)
            case "WEBP":return try WebPIntegrity().signature(reader)
            case "JPEG":return try JPEGIntegrity().signature(reader)
            case "PNG":return try PNGIntegrity().signature(reader)
            case "TIFF":return try TIFFIntegrity().signature(reader)
            case "HEIC","HEIF","AVIF":return try HEIFIntegrity().signature(reader,profile:profile.identifier)
            default:
                if profile.family == .raw {return try RAWIntegrity().signature(reader,profile:profile)}
                throw RestoreError(.unsupported,"No qualified media integrity parser is available for \(profile.identifier).")
            }
        }
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
    public func verify(before:MediaIntegritySignature,after:MediaIntegritySignature,allowedChanges:AllowedMetadataChanges) throws {
        guard before==after else {throw RestoreError(.verificationFailed,"Compressed media or required rendering/relationship data changed.")}
    }
}
