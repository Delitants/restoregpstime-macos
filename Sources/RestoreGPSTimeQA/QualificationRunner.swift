import Foundation
import Darwin
import RestoreGPSTimeCore

public struct QualificationRunner {
    public init() {}
    public func run(appURL:URL,fixtureManifest:URL,output:URL) async throws -> QualificationResult {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:output.path) else {throw RestoreError(.conflict,"Evidence output already exists; choose a fresh directory.")}
        try fm.createDirectory(at:output,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        func sysctl(_ name:String)->Int32? {var value:Int32=0,size=MemoryLayout<Int32>.size;return sysctlbyname(name,&value,&size,nil,0)==0 ? value:nil}
        func textSysctl(_ name:String)->String {var size=0;guard sysctlbyname(name,nil,&size,nil,0)==0,size>0,size<4096 else {return "unavailable"};var b=[CChar](repeating:0,count:size);guard sysctlbyname(name,&b,&size,nil,0)==0 else {return "unavailable"};return String(cString:b)}
        #if arch(arm64)
        let arch="arm64"
        #elseif arch(x86_64)
        let arch="x86_64"
        #else
        let arch="unknown"
        #endif
        let hardware=sysctl("hw.optional.arm64"),translation=sysctl("sysctl.proc_translated")
        // ENOENT for translation is expected on Intel; the hardware query still
        // has to succeed. Unknown sandbox-denied identity never means native.
        let translated:Bool?=translation.map {$0 != 0} ?? (hardware==0 ? false:(arch=="arm64" && hardware==1 ? false:nil))
        let version=ProcessInfo.processInfo.operatingSystemVersion
        let host=QualificationHost(processArchitecture:arch,hardwareARM:hardware.map {$0 != 0},translated:translated,osMajor:version.majorVersion,osVersion:"\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",osBuild:textSysctl("kern.osversion"))
        let buildURL=appURL.appendingPathComponent("Contents/Resources/build-identity.json")
        let build=(try? JSONSerialization.jsonObject(with:Data(contentsOf:buildURL))) as? [String:Any]
        let source=build?["sourceCommit"] as? String ?? "unrecorded"
        let executable=appURL.appendingPathComponent("Contents/MacOS/RestoreGPSTime")
        let hash=try await Task.detached {try FileIdentityReader().fingerprint(at:executable).contentHash}.value
        var gates=QualificationResult.requiredGates.map {QualificationGate($0,.missing,"Candidate-bound acceptance evidence has not been supplied.")}
        func set(_ id:String,_ state:GateStatus,_ detail:String) {if let i=gates.firstIndex(where:{$0.id==id}) {gates[i]=QualificationGate(id,state,detail)}}
        if source.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil,build?["sourceDirty"] as? Bool == false,build?["configuration"] as? String == "release",build?["architecture"] as? String == arch {
            set("source-identity",.pass,"Candidate records a clean release source commit and matching architecture.")
        } else {set("source-identity",.missing,"A clean matching release build identity has not been established.")}
        if let log=ProcessInfo.processInfo.environment["RESTOREGPSTIME_QA_REGRESSION_LOG"],let recorded=ProcessInfo.processInfo.environment["RESTOREGPSTIME_QA_REGRESSION_SOURCE"],let status=ProcessInfo.processInfo.environment["RESTOREGPSTIME_QA_REGRESSION_EXIT"] {
            let logURL=URL(fileURLWithPath:log)
            try fm.copyItem(at:logURL,to:output.appendingPathComponent("regression.log"))
            if status != "0" {set("baseline-regression",.fail,"Candidate regression command failed; local log retained.")}
            else if recorded==source,build?["sourceDirty"] as? Bool == false,host.isNative(architecture:arch) {set("baseline-regression",.pass,"Matching-source candidate regression command passed on this native host; local log retained.")}
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        do {
            let paths=try RuntimeLocator().locate(in:appURL),runtime=try await RuntimeProbe().inspect(paths:paths)
            let dependencies=try await DependencyIdentityProvider(paths:paths).observe()
            try encoder.encode(runtime).write(to:output.appendingPathComponent("runtime.json"),options:.withoutOverwriting)
            try encoder.encode(dependencies).write(to:output.appendingPathComponent("dependency-hashes.json"),options:.withoutOverwriting)
            guard runtime.exifToolVersion=="13.59",runtime.perlVersion=="5.44.0",runtime.architecture==arch,host.isNative(architecture:arch),runtime.loadedPaths.allSatisfy({$0.hasPrefix(paths.appBundle.path+"/")}) else {throw RestoreError(.verificationFailed,"Runtime version, architecture, native host identity or bundle-relative module isolation did not qualify.")}
            set("runtime",.pass,"Pinned bundled runtime executed natively; dependency hashes retained.")
        } catch {set("runtime",.fail,error.localizedDescription)}
        do {
            let fd=open(fixtureManifest.path,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
            guard fd>=0 else {throw RestoreError(.invalidInput,"Cannot open the local fixture manifest without following links.")}
            let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? handle.close()}
            var before=stat(),after=stat()
            guard fstat(fd,&before)==0,before.st_mode & S_IFMT==S_IFREG,before.st_size>=0,before.st_size<=1_048_576 else {throw RestoreError(.invalidInput,"Fixture manifest exceeds one MiB or is not an ordinary file.")}
            let data=try handle.read(upToCount:1_048_577) ?? Data()
            guard data.count<=1_048_576,fstat(fd,&after)==0,before.st_size==after.st_size,before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec else {throw RestoreError(.conflict,"Fixture manifest changed while reading it.")}
            let manifest=try JSONDecoder().decode(FixtureManifest.self,from:data)
            guard manifest.schema==1,!manifest.fixtures.isEmpty,manifest.fixtures.count<=10000,Set(manifest.fixtures.map(\.id)).count==manifest.fixtures.count else {throw RestoreError(.invalidInput,"Invalid or duplicated fixture inventory.")}
            for fixture in manifest.fixtures {
                guard !fixture.id.isEmpty,fixture.id != ".",fixture.id != "..",!fixture.id.contains("/"),!fixture.id.contains("\\"),!fixture.origin.isEmpty,!fixture.license.isEmpty else {throw RestoreError(.invalidInput,"Fixture names must be local file components with provenance and a license.")}
                let url=fixtureManifest.deletingLastPathComponent().appendingPathComponent(fixture.id)
                let actual=try await Task.detached {try FileIdentityReader().fingerprint(at:url).contentHash}.value
                guard actual==fixture.sha256 else {throw RestoreError(.verificationFailed,"Fixture checksum differs: "+fixture.id)}
            }
            try data.write(to:output.appendingPathComponent("fixture-manifest.json"),options:.withoutOverwriting)
            set("fixture-manifest",.pass,"All supplied fixture identities verified. This does not qualify genuine format behavior.")
        } catch {set("fixture-manifest",.fail,error.localizedDescription)}
        let result=QualificationResult(sourceCommit:source,appHash:hash,hostLabel:ProcessInfo.processInfo.environment["RESTOREGPSTIME_QA_HOST_LABEL"] ?? "local",host:host,gates:gates)
        try encoder.encode(result).write(to:output.appendingPathComponent("qualification-result.json"),options:.withoutOverwriting)
        return result
    }
}
private struct FixtureManifest:Decodable {let schema:Int,fixtures:[Fixture]}
private struct Fixture:Decodable {let id:String,origin:String,license:String,sha256:String}
