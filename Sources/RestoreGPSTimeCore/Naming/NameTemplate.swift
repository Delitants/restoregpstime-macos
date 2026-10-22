import Foundation

public struct NameTemplate:Codable,Equatable,Sendable {
    public let pattern:String
    public let preserveOriginal:Bool
    public init(_ pattern:String="{country} - {city} - {sequence:04}.{extension}",preserveOriginal:Bool=false) { self.pattern=pattern;self.preserveOriginal=preserveOriginal }
    public static let original=NameTemplate("",preserveOriginal:true)

    enum Part { case literal(String),field(String) }
    struct Parsed {
        let parts:[Part],width:Int?
        var fields:Set<String> { Set(parts.compactMap {if case .field(let key)=$0 {return key};return nil}) }
        func render(item:InspectedItem,place:PlaceMatch?,sequence:Int,limit:Int) throws -> (String,Bool) {
            var values=["country":place?.country ?? "","city":place?.city ?? "","original":item.snapshot.url.deletingPathExtension().lastPathComponent,"extension":item.snapshot.url.pathExtension,"sequence":String(format:"%0*d",width ?? 1,sequence)]
            for key in ["country","city","original","extension"] { values[key]=Self.sanitize(values[key] ?? "") }
            for key in ["country","city"] where fields.contains(key) {
                guard !(values[key] ?? "").isEmpty else {throw RestoreError(.missingMetadata,"Choose a \(key) before using it in the filename.")}
            }
            guard !(values["extension"] ?? "").isEmpty else { throw RestoreError(.unsupported,"A metadata rename requires a file extension.") }
            func output()->String { parts.map { switch $0 {case .literal(let s):return s;case .field(let k):return values[k] ?? ""} }.joined() }
            let full=output();var rendered=full
            let mutable=["country","city","original"].filter {fields.contains($0)}
            for key in mutable { values[key]=Self.prefix(values[key]!,bytes:limit) }
            rendered=output()
            while rendered.utf8.count>limit {
                var longest:String?
                for key in mutable where longest==nil || values[key]!.utf8.count>values[longest!]!.utf8.count {longest=key}
                guard let key=longest,!values[key]!.isEmpty else { throw RestoreError(.unsupported,"The sequence, extension and template exceed the volume filename limit.") }
                let budget=max(0,values[key]!.utf8.count-(rendered.utf8.count-limit))
                values[key]=Self.prefix(values[key]!,bytes:budget);rendered=output()
            }
            guard Self.validComponent(rendered) else { throw RestoreError(.invalidInput,"The template produces an invalid filename.") }
            return (rendered,rendered != full)
        }
        static func sanitize(_ value:String)->String {
            let scalars=value.precomposedStringWithCanonicalMapping.unicodeScalars.map { c in
                c == "/" || c == ":" || CharacterSet.controlCharacters.contains(c) ? "-" : String(c)
            }.joined()
            return scalars.trimmingCharacters(in:CharacterSet(charactersIn:" ."))
        }
        static func prefix(_ value:String,bytes:Int)->String {
            var out="",used=0
            for character in value { let count=String(character).utf8.count;if used+count>bytes {break};out.append(character);used+=count }
            return out
        }
        static func validComponent(_ value:String)->Bool { !value.isEmpty && value != "." && value != ".." && !value.unicodeScalars.contains(where:{$0 == "/" || $0 == ":" || CharacterSet.controlCharacters.contains($0)}) }
    }
    func parsed() throws -> Parsed {
        if preserveOriginal { return .init(parts:[],width:nil) }
        guard !pattern.isEmpty,pattern.utf8.count<=4096,pattern.hasSuffix(".{extension}") else { throw RestoreError(.invalidInput,"A rename template must end with .{extension}.") }
        var parts=[Part](),remaining=pattern[...],seen=Set<String>(),width:Int?
        while !remaining.isEmpty {
            if remaining.first == "{" {
                guard let close=remaining.firstIndex(of:"}") else { throw RestoreError(.invalidInput,"Unclosed filename field.") }
                let token=String(remaining[remaining.index(after:remaining.startIndex)..<close]);let key:String
                if token.hasPrefix("sequence:") {
                    let digits=String(token.dropFirst(9))
                    guard digits.count<=2,digits.allSatisfy({$0.isASCII && $0.isNumber}),let n=Int(digits),(1...9).contains(n) else { throw RestoreError(.invalidInput,"Use a sequence width from 1 to 9.") }
                    key="sequence";width=n
                } else { key=token }
                guard ["country","city","original","extension","sequence"].contains(key),key != "sequence" || width != nil,seen.insert(key).inserted else { throw RestoreError(.invalidInput,"Unknown or repeated filename field: \(token).") }
                parts.append(.field(key));remaining=remaining[remaining.index(after:close)...]
            } else {
                let end=remaining.firstIndex(of:"{") ?? remaining.endIndex
                let literal=String(remaining[..<end])
                guard !literal.contains("}"),!literal.unicodeScalars.contains(where:{$0 == "/" || $0 == ":" || CharacterSet.controlCharacters.contains($0)}) else { throw RestoreError(.invalidInput,"Filename templates cannot contain paths or control characters.") }
                parts.append(.literal(literal));remaining=remaining[end...]
            }
        }
        return .init(parts:parts,width:width)
    }
}
