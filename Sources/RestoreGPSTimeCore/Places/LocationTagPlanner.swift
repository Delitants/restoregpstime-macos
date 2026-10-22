import Foundation

public enum CommentMode:String,Codable,Sendable { case appendOnce,replace }
public enum LocationCommentDestination:String,Codable,Sendable { case automatic,exif,xmp,quickTime }
public struct LocationWriteOptions:Codable,Equatable,Sendable {
    public var writeComment=true
    public var writeStructuredFields=false
    public var mode:CommentMode = .appendOnce
    public var destination:LocationCommentDestination = .automatic
    public init() {}
}
public struct LocationTagPlanner {
    public init() {}
    public func plan(match:PlaceMatch,document:MetadataDocument,options:LocationWriteOptions) throws -> [TagMutation] {
        guard !match.displayName.isEmpty else { throw RestoreError(.invalidInput,"Location text cannot be empty.") }
        var mutations=[TagMutation]()
        if options.writeComment {
            let tag:String,existingTag:String
            switch options.destination {
            case .exif:
                guard document.profile.family != .video else { throw RestoreError(.unsupported,"Select a QuickTime or XMP comment destination for video.") }
                tag="ExifIFD:UserComment";existingTag=tag
            case .xmp:tag="XMP-dc:Description-x-default";existingTag="XMP-dc:Description"
            case .quickTime:
                guard document.profile.family == .video else { throw RestoreError(.unsupported,"QuickTime comments require a video profile.") }
                tag="Keys:Description-und";existingTag="Keys:Description"
            case .automatic:
                if document.profile.family == .video { tag="Keys:Description-und";existingTag="Keys:Description" }
                else if ["JPEG","HEIC","HEIF","TIFF"].contains(document.profile.identifier) || document.profile.family == .raw { tag="ExifIFD:UserComment";existingTag=tag }
                else { tag="XMP-dc:Description-x-default";existingTag="XMP-dc:Description" }
            }
            let existing=document.tags[tag]?.text ?? document.tags[existingTag]?.text ?? ""
            var text=match.displayName
            if options.mode == .appendOnce && !existing.isEmpty {
                let already=existing.components(separatedBy:.newlines).contains {$0.trimmingCharacters(in:.whitespaces)==text}
                text=already ? existing:existing+"\n"+text
            }
            mutations.append(.set(TagID(rawValue:tag)!,.string(text)))
        }
        if options.writeStructuredFields {
            for (tag,value) in [("XMP-photoshop:City",match.city),("XMP-photoshop:State",match.region),("XMP-photoshop:Country",match.country),("XMP-iptcCore:CountryCode",match.countryCode)] where !value.isEmpty { mutations.append(.set(TagID(rawValue:tag)!,.string(value))) }
        }
        return mutations
    }
}
