import Foundation
import Darwin

public struct WorkflowStore:Sendable {
    public init() {}
    public func encode(_ document:WorkflowDocument) throws -> Data {
        try validate(document)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(document)
        guard data.count<=1_048_576 else {throw invalid("Workflow exceeds one MiB")}
        return data
    }
    public func decode(_ data:Data) throws -> WorkflowDocument {
        guard data.count<=1_048_576 else {throw invalid("Workflow exceeds one MiB")}
        let document=try JSONDecoder().decode(WorkflowDocument.self,from:data)
        try validate(document)
        // Codable ignores unknown struct keys. Require the complete data-only
        // schema to round-trip so no hidden operation or executable field survives.
        guard let input=try JSONSerialization.jsonObject(with:data) as? [String:Any],let canonical=try JSONSerialization.jsonObject(with:encode(document)) as? [String:Any],(input as NSDictionary).isEqual(canonical as NSDictionary) else {throw invalid("Unknown or noncanonical workflow fields")}
        return document
    }
    public func load(from url:URL) throws -> WorkflowDocument {
        guard url.isFileURL,url.pathExtension.lowercased()=="rgtimeworkflow" else {throw invalid("Choose a .rgtimeworkflow file")}
        return try decode(Self.readBounded(url,limit:1_048_576))
    }
    public func save(_ document:WorkflowDocument,to url:URL) throws {
        guard url.isFileURL,url.pathExtension.lowercased()=="rgtimeworkflow" else {throw invalid("Choose a .rgtimeworkflow filename")}
        let data=try encode(document)
        if FileManager.default.fileExists(atPath:url.path) {
            guard try FileIdentityReader().snapshot(at:url).kind == .regular else {throw invalid("Workflow destination is not an ordinary file")}
        }
        try data.write(to:url,options:.atomic)
        guard chmod(url.path,0o600)==0 else {throw invalid("Could not restrict workflow file permissions")}
    }
    static func readBounded(_ url:URL,limit:Int,privateFile:Bool=false) throws -> Data {
        let fd=open(url.path,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw RestoreError(.io,"Cannot open data file without following links.")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? handle.close()}
        var before=stat(),after=stat()
        guard fstat(fd,&before)==0,before.st_mode & S_IFMT==S_IFREG,before.st_size<=limit,!privateFile || before.st_uid==getuid() && before.st_mode & 0o077==0 && before.st_nlink==1 else {throw RestoreError(.invalidInput,"The data file exceeds its bound or has unsafe attributes.")}
        let data=try handle.read(upToCount:limit+1) ?? Data()
        guard data.count<=limit,fstat(fd,&after)==0,before.st_size==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec else {throw RestoreError(.conflict,"The data file changed while reading it.")}
        return data
    }
    private func validate(_ document:WorkflowDocument) throws {
        let request=document.request
        guard document.schema==1 else {throw invalid("Unsupported workflow schema")}
        guard !document.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,document.name.utf8.count<=512,!document.name.utf8.contains(0) else {throw invalid("Enter a bounded workflow name")}
        guard request.placeOverrides.isEmpty,request.excludedSourceKeys.isEmpty,request.groups.unlinkedSourceKeys.isEmpty,request.groups.forcedGroups.isEmpty else {throw invalid("Workflow contains per-file data")}
        if let query=request.placeQuery {
            guard query.maxDistanceKM.isFinite,query.maxDistanceKM>0,query.maxDistanceKM<=20050,(1...10).contains(query.limit) else {throw invalid("Invalid offline lookup radius or candidate count")}
        }
        _=try request.rename.parsed()
        if request.trashHiddenFiles {guard request.dates==nil,request.location==nil,request.tags.isEmpty,!request.removeGPS,!request.stripMetadata,request.rename.preserveOriginal,request.finder.isEmpty,request.metadataDestination == .embedded else {throw invalid("Trash cleanup must be a separate workflow")}}
        if let policy=request.dates {
            guard policy.shiftSeconds.isFinite,policy.sequenceStepSeconds.isFinite,policy.fixedOffsetSeconds.map({(-64_800...64_800).contains($0)}) ?? true else {throw invalid("Invalid date shift or offset")}
            if let zone=policy.timeZoneID,TimeZone(identifier:zone)==nil {throw invalid("Unknown time zone")}
            switch policy.source {
            case .tag(let key):guard TagID(rawValue:key) != nil else {throw invalid("Invalid qualified date tag")}
            case .filename(let pattern):guard pattern.utf8.count<=4096,!pattern.contains("/"),!pattern.utf8.contains(0) else {throw invalid("Invalid filename date pattern")}
            case .spotlight(let field):guard ["kMDItemContentCreationDate","kMDItemContentModificationDate","kMDItemDateAdded","kMDItemDownloadedDate"].contains(field) else {throw invalid("Unsupported Spotlight date field")}
            case .specific(let date):guard date.timeIntervalSince1970.isFinite else {throw invalid("Invalid specific date")}
            default:break
            }
            if let start=policy.sequenceStart,!start.timeIntervalSince1970.isFinite {throw invalid("Invalid sequence date")}
        }
        let registry=TagRegistry();var selected=Set<String>()
        for mutation in request.tags {
            let id:TagID;switch mutation {case .set(let key,_),.remove(let key):id=key}
            let actual=try registry.definition(id).0
            guard selected.insert(actual).inserted else {throw invalid("Repeated tag destination")}
            let video=["Keys:","QuickTime:","UserData:","ItemList:"].contains {actual.hasPrefix($0)}
            try registry.validate([mutation],profile:.init(identifier:video ? "MOV":"JPEG",family:video ? .video:.photo))
        }
        guard request.tags.count<=512 else {throw invalid("Too many workflow tag changes")}
        for mutation in request.finder {
            switch mutation {
            case .creator(let data),.fileType(let data):guard data.count==4 else {throw invalid("Legacy Finder codes require four bytes")}
            case .label(let number):guard (0...7).contains(number) else {throw invalid("Invalid Finder label")}
            default:break
            }
        }
    }
    private func invalid(_ message:String)->RestoreError {.init(.invalidInput,message+".")}
}
