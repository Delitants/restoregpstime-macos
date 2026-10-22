import Foundation

public struct CaptureDateResolver {
    public init() {}
    public func resolve(document:MetadataDocument,snapshot:FileSnapshot,policy:DatePolicy) throws -> DateResolution {
        let tags:[String],automatic:Bool
        switch policy.source {
        case .tag(let tag): tags=[tag];automatic=false
        case .automaticCapture:
            automatic=true
            tags=document.profile.family == .video ? ["Keys:CreationDate","QuickTime:CreationDate","XMP-exif:DateTimeOriginal","XMP-xmp:CreateDate","QuickTime:CreateDate","Track1:MediaCreateDate","Track1:TrackCreateDate"] : ["ExifIFD:DateTimeOriginal","XMP-exif:DateTimeOriginal","XMP-xmp:CreateDate","ExifIFD:CreateDate"]
        case .fileCreation: return Self.instant(snapshot.creationDate,source:"File creation date")
        case .fileModification: return Self.instant(snapshot.modificationDate,source:"File modification date")
        case .specific(let date): return Self.instant(date,source:"Specific date")
        default: throw RestoreError(.invalidInput,"This date source requires its explicit reference context.")
        }
        var warnings=[String]()
        for tag in tags {
            guard let raw=document.tags[tag]?.text,!raw.isEmpty else { continue }
            do {
                let parsed=try WallClockParser().parse(raw)
                var offset=parsed.explicitOffset,fraction=parsed.fraction,precision=parsed.fractionalPrecision
                if tag.hasPrefix("ExifIFD:") || tag.hasPrefix("IFD0:") {
                    let suffix=tag.hasSuffix(":DateTimeOriginal") ? "Original" : (tag.hasSuffix(":CreateDate") ? "Digitized":"")
                    if offset==nil,let text=document.tags["ExifIFD:OffsetTime"+suffix]?.text { offset=try WallClockParser().parseOffset(text) }
                    if precision==0,let text=document.tags["ExifIFD:SubSecTime"+suffix]?.text,!text.isEmpty {
                        guard text.range(of:#"^\d{1,9}$"#,options:.regularExpression) != nil else { throw RestoreError(.invalidInput,"Invalid fractional capture seconds.") }
                        fraction=Double("0."+text)!;precision=text.count
                    }
                }
                let wall=WallClock(year:parsed.year,month:parsed.month,day:parsed.day,hour:parsed.hour,minute:parsed.minute,second:parsed.second,fraction:fraction,fractionalPrecision:precision,explicitOffset:offset)
                let integer=tag.range(of:#"^(QuickTime|Track\d+):(CreateDate|ModifyDate|MediaCreateDate|MediaModifyDate|TrackCreateDate|TrackModifyDate)$"#,options:.regularExpression) != nil
                let resolved=try TimezoneResolver().resolve(wall,policy:policy,quickTimeInteger:integer)
                return .init(source:tag,original:raw,instant:resolved.instant,offsetSeconds:resolved.offset,fractionalPrecision:precision,interpretation:resolved.interpretation,warnings:warnings)
            } catch let error as RestoreError where automatic && error.code == .invalidInput { warnings.append("\(tag): \(error.detail)") }
        }
        throw RestoreError(.missingMetadata,"No valid date was found for the selected source. "+warnings.joined(separator:" "))
    }
    static func instant(_ date:Date,source:String,warnings:[String]=[]) -> DateResolution {
        .init(source:source,original:ISO8601DateFormatter().string(from:date),instant:date,offsetSeconds:0,fractionalPrecision:fractionalPrecision(date.timeIntervalSince1970),interpretation:"Existing absolute instant",warnings:warnings)
    }
    static func fractionalPrecision(_ seconds:Double)->Int {
        let fraction=seconds-floor(seconds)
        if fraction==0 {return 0}
        // Date uses binary floating point. Permit its ULP when inferring a decimal precision.
        for digits in 1...9 {
            let scale=pow(10,Double(digits))
            if abs(fraction-(fraction*scale).rounded()/scale)<=max(seconds.ulp*2,0.0000000005) {return digits}
        }
        return 9
    }
}
