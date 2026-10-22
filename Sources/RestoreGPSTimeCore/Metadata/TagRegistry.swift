import Foundation

public struct TagRegistry:Sendable {
    let tags:[String:String]
    public init() {
        let shipped=Bundle.main.url(forResource:"writable-tags",withExtension:"json")
        let local=Bundle.main.bundleURL.pathExtension=="app" ? nil:Bundle.module.url(forResource:"writable-tags",withExtension:"json")
        if let url=shipped ?? local,let data=try? Data(contentsOf:url),let registry=try? JSONDecoder().decode(Registry.self,from:data),registry.schema==1 {tags=registry.tags} else {tags=[:]}
    }
    public var identifiers:[String] {tags.keys.sorted()}
    func definition(_ id:TagID) throws -> (String,String) {
        guard TagID(rawValue:id.rawValue) != nil else {throw RestoreError(.invalidInput,"Invalid qualified metadata field.")}
        if let type=tags[id.rawValue] {
            if type=="language" {return (id.rawValue+"-x-default",type)}
            if type=="quickTimeLanguage" {return (id.rawValue+"-und",type)}
            return (id.rawValue,type)
        }
        for (key,type) in tags where ["language","quickTimeLanguage"].contains(type) && id.rawValue.hasPrefix(key+"-") {
            let language=String(id.rawValue.dropFirst(key.count+1))
            guard language.range(of:"\\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\\z",options:.regularExpression) != nil || language=="x-default" || language=="und" else {throw RestoreError(.invalidInput,"Invalid metadata language code.")}
            return (id.rawValue,type)
        }
        if MetadataStripProfiles.removableLocation(id.rawValue) {return (id.rawValue,"removalOnly")}
        throw RestoreError(.unsupported,"The field is not a qualified writable descriptive tag: \(id.rawValue).")
    }
    public func validate(_ mutations:[TagMutation],profile:ContainerProfile) throws {
        guard mutations.count<=512 else {throw RestoreError(.invalidInput,"Too many selected metadata fields.")}
        var seen=Set<String>(),textBytes=0
        for mutation in mutations {
            let id:TagID,value:TagValue?
            switch mutation {case .set(let tag,let item):id=tag;value=item;case .remove(let tag):id=tag;value=nil}
            let (actual,type)=try definition(id)
            guard seen.insert(actual).inserted else {throw RestoreError(.invalidInput,"The same metadata destination is selected twice.")}
            if profile.identifier=="XMP" && !actual.hasPrefix("XMP-") {throw RestoreError(.unsupported,"An XMP sidecar accepts only qualified XMP fields.")}
            if profile.family == .video && !["XMP-","Keys:","QuickTime:","ItemList:","UserData:"].contains(where:{actual.hasPrefix($0)}) {throw RestoreError(.unsupported,"This embedded namespace is not qualified for video writing.")}
            if actual.hasPrefix("Keys:") || actual.hasPrefix("QuickTime:") || actual.hasPrefix("ItemList:") || actual.hasPrefix("UserData:") {
                guard profile.family == .video else {throw RestoreError(.unsupported,"QuickTime fields require a qualified video profile.")}
            }
            guard let value else {continue}
            if case .array(let entries)=value {textBytes+=entries.reduce(0,{$0+$1.text.utf8.count})}
            else {textBytes+=value.text.utf8.count}
            guard textBytes<=1_048_576 else {throw RestoreError(.unsupported,"The selected metadata values exceed the one MiB batch-field limit.")}
            if type=="removalOnly" {throw RestoreError(.unsupported,"This location field is qualified only for removal.")}
            if type=="list" {
                guard case .array(let entries)=value,entries.count<=1024,entries.allSatisfy({if case .string(let text)=$0 {return text.utf8.count<=1_048_576 && !text.utf8.contains(0)};return false}) else {throw RestoreError(.invalidInput,"This metadata field requires a bounded list of text values.")}
            } else if ["latitude","longitude","number","rating","altitudeRef"].contains(type) {
                guard let number=value.double,number.isFinite else {throw RestoreError(.invalidInput,"Metadata numbers must be finite.")}
                if type=="latitude" && !(-90...90).contains(number) || type=="longitude" && !(-180...180).contains(number) || type=="rating" && !(-1...5).contains(number) || type=="altitudeRef" && ![0.0,1].contains(number) {throw RestoreError(.invalidInput,"The metadata number is out of range.")}
            } else {
                guard case .string(let text)=value,text.utf8.count<=1_048_576,!text.utf8.contains(0) else {throw RestoreError(.invalidInput,"This metadata field requires bounded text without NUL bytes.")}
                if type=="digits" && (text.isEmpty || text.count>9 || !text.allSatisfy({$0.isASCII && $0.isNumber})) {throw RestoreError(.invalidInput,"Subseconds require one to nine decimal digits.")}
                if type=="latitudeRef" && !["N","S"].contains(text) || type=="longitudeRef" && !["E","W"].contains(text) {throw RestoreError(.invalidInput,"Invalid GPS hemisphere reference.")}
                if type=="date" {_ = try WallClockParser().parse(text)}
                if type=="offset" {_ = try WallClockParser().parse("2000:01:01 00:00:00"+text)}
            }
        }
    }
    public func value(for id:TagID,in document:MetadataDocument)->TagValue? {
        if let value=document.tags[id.rawValue] {return value}
        for suffix in ["-x-default","-und"] where id.rawValue.hasSuffix(suffix) {return document.tags[String(id.rawValue.dropLast(suffix.count))]}
        if let (actual,_)=try? definition(id),actual != id.rawValue {return document.tags[actual] ?? document.tags[id.rawValue]}
        return nil
    }
}
private struct Registry:Decodable {let schema:Int;let tags:[String:String]}
