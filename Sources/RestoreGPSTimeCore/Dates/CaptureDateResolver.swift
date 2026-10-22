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
        case .fileCreation: return Self.instant(snapshot.creationDate,source:"File creation date",exactTimestamp:snapshot.creationTimestamp)
        case .fileModification: return Self.instant(snapshot.modificationDate,source:"File modification date",exactTimestamp:snapshot.modificationTimestamp)
        case .specific(let date): return Self.instant(date,source:"Specific date")
        default: throw RestoreError(.invalidInput,"This date source requires its explicit reference context.")
        }
        var warnings=[String]()
        for tag in tags {
            guard let raw=try document.readValue(tag)?.text,!raw.isEmpty else { continue }
            do {
                let parsed=try WallClockParser().parse(raw)
                var offset=parsed.explicitOffset,fraction=parsed.fraction,precision=parsed.fractionalPrecision,nanoseconds=parsed.nanoseconds
                if tag.hasPrefix("ExifIFD:") || tag.hasPrefix("IFD0:") {
                    let suffix=tag.hasSuffix(":DateTimeOriginal") ? "Original" : (tag.hasSuffix(":CreateDate") ? "Digitized":"")
                    if offset==nil,let text=try document.readValue("ExifIFD:OffsetTime"+suffix)?.text { offset=try WallClockParser().parseOffset(text) }
                    if precision==0,let text=try document.readValue("ExifIFD:SubSecTime"+suffix)?.text,!text.isEmpty {
                        guard text.range(of:#"^[0-9]{1,9}$"#,options:.regularExpression) != nil,let subsecond=Double("0."+text),let exactNanos=Int32(text+String(repeating:"0",count:9-text.count)) else { throw RestoreError(.invalidInput,"Invalid fractional capture seconds.") }
                        fraction=subsecond;precision=text.count;nanoseconds=exactNanos
                    }
                }
                let wall=WallClock(year:parsed.year,month:parsed.month,day:parsed.day,hour:parsed.hour,minute:parsed.minute,second:parsed.second,fraction:fraction,fractionalPrecision:precision,explicitOffset:offset,nanoseconds:nanoseconds)
                let integer=tag.range(of:#"^(QuickTime|Track\d+):(CreateDate|ModifyDate|MediaCreateDate|MediaModifyDate|TrackCreateDate|TrackModifyDate)$"#,options:.regularExpression) != nil
                let resolved=try TimezoneResolver().resolve(wall,policy:policy,quickTimeInteger:integer)
                let whole=try WallClockParser().utcBase(wall).timeIntervalSince1970-Double(resolved.offset)
                let exact=try FileTimestamp(seconds:Int64(whole),nanoseconds:nanoseconds ?? Int32((fraction*1e9).rounded()))
                return .init(source:tag,original:raw,instant:exact.date,offsetSeconds:resolved.offset,fractionalPrecision:precision,interpretation:resolved.interpretation,warnings:warnings,exactTimestamp:exact)
            } catch let error as RestoreError where automatic && error.code == .invalidInput { warnings.append("\(tag): \(error.detail)") }
        }
        throw RestoreError(.missingMetadata,"No valid date was found for the selected source. "+warnings.joined(separator:" "))
    }
    static func instant(_ date:Date,source:String,warnings:[String]=[],exactTimestamp:FileTimestamp?=nil) -> DateResolution {
        let precision=exactTimestamp?.fractionalPrecision ?? fractionalPrecision(date.timeIntervalSince1970)
        let exact=exactTimestamp ?? (try? FileTimestamp(date:date).rounded(precision:precision))
        return .init(source:source,original:ISO8601DateFormatter().string(from:date),instant:exact?.date ?? date,offsetSeconds:0,fractionalPrecision:precision,interpretation:"Existing absolute instant",warnings:warnings,exactTimestamp:exact)
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
