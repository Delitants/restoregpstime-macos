import Foundation

public actor ExifToolWriter {
    let paths:RuntimePaths
    let registry=TagRegistry()
    let reader:MetadataReader
    public init(paths:RuntimePaths) {self.paths=paths;reader=MetadataReader(paths:paths)}
    public func write(_ mutations:[TagMutation],to stage:URL,profile:ContainerProfile) async throws -> MetadataDocument {
        try StageOwnership.shared.require(stage,kind:.regular);try registry.validate(mutations,profile:profile)
        guard mutations.count<=512 else {throw RestoreError(.invalidInput,"Too many metadata field changes in one operation.")}
        var args=["-overwrite_original_in_place","-P","-n","-charset","filename=UTF8","-api","LargeFileSupport=1","-api","QuickTimeUTC=1"]
        for mutation in mutations {
            let id:TagID,value:TagValue?
            switch mutation {case .set(let tag,let item):id=tag;value=item;case .remove(let tag):id=tag;value=nil}
            let (tag,_)=try registry.definition(id)
            if let value {
                if case .array(let values)=value {
                    if values.isEmpty {args.append("-\(tag)=")}
                    // Repeated assignments replace a list. += would append to the file's old list.
                    // https://exiftool.org/exiftool_pod.html#TAG-VALUE
                    for entry in values {args.append(try argument(tag:tag,operation:"=",text:entry.text,stage:stage))}
                } else {args.append(try argument(tag:tag,operation:"=",text:value.text,stage:stage))}
            } else {args.append("-\(tag)=")}
        }
        guard args.reduce(0,{$0+$1.utf8.count+1})<=131072 else {throw RestoreError(.unsupported,"The metadata request exceeds the bounded helper argument size.")}
        if !mutations.isEmpty {try await run(args,to:stage)}
        let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
        for mutation in mutations {
            switch mutation {
            case .remove(let id):guard registry.value(for:id,in:after)==nil else {throw RestoreError(.verificationFailed,"The selected field remains after removal: \(id.rawValue).")}
            case .set(let id,let expected):
                let actual=registry.value(for:id,in:after)
                if case .array(let list)=expected,list.isEmpty,actual==nil {continue}
                guard let actual else {throw RestoreError(.verificationFailed,"The selected field was not written: \(id.rawValue).")}
                let (_,type)=try registry.definition(id)
                let matches:Bool
                if type=="date",let a=try? WallClockParser().parse(actual.text),let b=try? WallClockParser().parse(expected.text) {matches=a.year==b.year && a.month==b.month && a.day==b.day && a.hour==b.hour && a.minute==b.minute && a.second==b.second && abs(a.fraction-b.fraction)<0.000000001 && a.explicitOffset==b.explicitOffset}
                else if ["latitude","longitude","number","rating","altitudeRef"].contains(type),let a=actual.double,let b=expected.double {matches=abs(a-b)<0.0000001}
                else if type=="list" {matches=actual==expected}
                else {matches=actual.text==expected.text}
                guard matches else {throw RestoreError(.verificationFailed,"Read-back differs from the selected value: \(id.rawValue).")}
            }
        }
        return after
    }
    private func argument(tag:String,operation:String,text:String,stage:URL) throws -> String {
        if text.utf8.count<=4096 {return "-\(tag)\(operation)\(text)"}
        guard operation=="=" else {throw RestoreError(.unsupported,"A single list entry exceeds the inline metadata limit.")}
        let valueFile=stage.deletingLastPathComponent().appendingPathComponent(".field-value-\(UUID().uuidString)")
        try Data(text.utf8).write(to:valueFile,options:.withoutOverwriting)
        return "-\(tag)<=\(valueFile.path)"
    }
    func run(_ arguments:[String],to stage:URL) async throws {
        try StageOwnership.shared.require(stage,kind:.regular)
        let size=try FileIdentityReader().snapshot(at:stage).id.size
        let timeout=max(60,min(21600,60+Double(size)/1_000_000))
        await HelperLimiter.shared.acquire()
        let outcome:Result<Void,Error>
        do {
            try Task.checkCancellation()
            let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(arguments+["--",stage.path]),environment:paths.environment,timeout:timeout)
            guard result.exitStatus==0 else {throw RestoreError(.processFailed,"Metadata helper failed: "+String(decoding:result.stderr,as:UTF8.self))}
            try StageOwnership.shared.refresh(stage);outcome = .success(())
        } catch {outcome = .failure(error)}
        await HelperLimiter.shared.release();try outcome.get()
    }
}

extension ExifToolWriter {
    func removeXMPLocation(to stage:URL) async throws {
        try StageOwnership.shared.require(stage,kind:.regular)
        await HelperLimiter.shared.acquire()
        let outcome:Result<Data,Error>
        do {
            let result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(["-b","-XMP","--",stage.path]),environment:paths.environment,timeout:60)
            guard result.exitStatus==0 else {throw RestoreError(.processFailed,"Cannot inspect the stage XMP packet.")}
            outcome = .success(result.stdout)
        } catch {outcome = .failure(error)}
        await HelperLimiter.shared.release()
        let data=try outcome.get()
        if data.isEmpty {return}
        guard let cleaned=try XMPGPSRemover().clean(data) else {return}
        let packet=stage.deletingLastPathComponent().appendingPathComponent(".location-removed-\(UUID().uuidString).xmp")
        try cleaned.write(to:packet,options:.withoutOverwriting)
        try await run(["-overwrite_original_in_place","-P","-XMP:all="],to:stage)
        try await run(["-overwrite_original_in_place","-P","-XMP<=\(packet.path)"],to:stage)
    }
}
