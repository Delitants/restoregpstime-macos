import Foundation

struct EmbeddedDateTags {
    func mutations(_ change:DateMutation,profile:ContainerProfile,document:MetadataDocument?=nil) throws -> [TagMutation] {
        let existingExif=document?.tags["ExifIFD:DateTimeOriginal"] != nil
        let xmp=profile.identifier=="XMP" || (["PNG","WEBP","AVIF"].contains(profile.identifier) && !existingExif)
        let video=profile.family == .video
        let primary=xmp ? "XMP-exif:DateTimeOriginal":(video ? "Keys:CreationDate":"ExifIFD:DateTimeOriginal")
        if change.removeEmbeddedDates {
            let ids=xmp || video ? [primary]:[primary,"ExifIFD:SubSecTimeOriginal","ExifIFD:OffsetTimeOriginal"]
            return ids.map {.remove(TagID(rawValue:$0)!)}
        }
        guard let date=change.embeddedDate else {return []}
        guard change.embeddedOffsetSeconds % 60 == 0,(-64800...64800).contains(change.embeddedOffsetSeconds) else {throw RestoreError(.unsupported,"This embedded date field cannot represent an offset with seconds or beyond 18 hours.")}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian);formatter.timeZone=TimeZone(secondsFromGMT:change.embeddedOffsetSeconds)
        formatter.dateFormat=xmp ? "yyyy-MM-dd'T'HH:mm:ss":"yyyy:MM:dd HH:mm:ss"
        let precision=max(0,min(9,change.embeddedPrecision))
        let exact=try change.embeddedTimestamp ?? FileTimestamp(date:date).rounded(precision:precision)
        guard exact.fractionalPrecision<=precision else {throw RestoreError(.unsupported,"The selected embedded precision would discard capture fractions.")}
        let base=formatter.string(from:Date(timeIntervalSince1970:Double(exact.seconds)))
        let digits=precision==0 ? "":String(String(format:"%09d",exact.nanoseconds).prefix(precision))
        let offset=change.embeddedOffsetSeconds,absolute=abs(offset)
        let zone=String(format:"%@%02d:%02d",offset<0 ? "-":"+",absolute/3600,absolute/60%60)
        if xmp || video {return [.set(TagID(rawValue:primary)!,.string(base+(digits.isEmpty ? "":"."+digits)+zone))]}
        return [.set(TagID(rawValue:primary)!,.string(base)),.set(TagID(rawValue:"ExifIFD:OffsetTimeOriginal")!,.string(zone)),digits.isEmpty ? .remove(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!):.set(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!,.string(digits))]
    }
}
