import Foundation

public struct FilenameDateParser {
    public init() {}
    public func parse(filename:String,pattern:String) throws -> String {
        let tokens=[("yyyy",#"\d{4}"#),("XXXXX",#"Z|[+-]\d{2}:\d{2}"#),("SSS",#"\d{3}"#),("MM",#"\d{2}"#),("dd",#"\d{2}"#),("HH",#"\d{2}"#),("mm",#"\d{2}"#),("ss",#"\d{2}"#)]
        var regex="",fields=[String](),index=pattern.startIndex
        while index<pattern.endIndex {
            if let token=tokens.first(where:{pattern[index...].hasPrefix($0.0)}) {
                guard !fields.contains(token.0) else { throw RestoreError(.invalidInput,"Date pattern repeats a field.") }
                fields.append(token.0);regex+="("+token.1+")";index=pattern.index(index,offsetBy:token.0.count)
            } else { regex+=NSRegularExpression.escapedPattern(for:String(pattern[index]));index=pattern.index(after:index) }
        }
        guard ["yyyy","MM","dd"].allSatisfy(fields.contains) else { throw RestoreError(.invalidInput,"Filename date patterns require yyyy, MM and dd.") }
        let matches=try NSRegularExpression(pattern:regex).matches(in:filename,range:NSRange(filename.startIndex...,in:filename))
        guard matches.count==1,let match=matches.first else { throw RestoreError(matches.isEmpty ? .missingMetadata:.conflict,"The filename must contain exactly one matching date.") }
        var values=[String:String]()
        for (i,field) in fields.enumerated() { values[field]=String(filename[Range(match.range(at:i+1),in:filename)!]) }
        let value="\(values["yyyy"]!):\(values["MM"]!):\(values["dd"]!) \(values["HH"] ?? "00"):\(values["mm"] ?? "00"):\(values["ss"] ?? "00")"+(values["SSS"].map {"."+$0} ?? "")+(values["XXXXX"] ?? "")
        _=try WallClockParser().parse(value)
        return value
    }
}
