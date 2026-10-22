import Foundation
import Darwin

public enum DropletSignature:String,Sendable {case adHocLocal}
public struct DropletExportResult:Sendable {public let bundleURL:URL,bundleIdentifier:String,signature:DropletSignature}
public struct DropletExporter:Sendable {
    public init() {}
    public func export(workflow:WorkflowDocument,to appURL:URL,template:URL) async throws -> DropletExportResult {
        let worker=Task.detached {try await build(workflow:workflow,to:appURL,template:template)}
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
    private func build(workflow:WorkflowDocument,to appURL:URL,template:URL) async throws -> DropletExportResult {
        _=try WorkflowStore().encode(workflow)
        guard appURL.isFileURL,appURL.pathExtension.lowercased()=="app",!SecureFS.exists(appURL) else {throw RestoreError(.conflict,"Choose a new .app destination; an existing export is never replaced.")}
        let parent=try FileSystemPath.canonicalDirectory(appURL.deletingLastPathComponent()),output=parent.appendingPathComponent(appURL.lastPathComponent,isDirectory:true)
        let executable=template.appendingPathComponent("Contents/MacOS/RestoreGPSTimeDroplet"),policy=template.appendingPathComponent("Contents/Resources/writable-tags.json")
        let snapshot=try FileIdentityReader().snapshot(at:executable)
        guard snapshot.kind == .regular,snapshot.id.size<=67_108_864 else {throw RestoreError(.runtimeUnavailable,"The native droplet template is missing or too large.")}
        let handle=try FileHandle(forReadingFrom:executable);let header=try handle.read(upToCount:4) ?? Data();try handle.close()
        guard [Data([0xcf,0xfa,0xed,0xfe]),Data([0xca,0xfe,0xba,0xbe]),Data([0xca,0xfe,0xba,0xbf])].contains(header) else {throw RestoreError(.runtimeUnavailable,"The droplet template is not a native Mach-O executable.")}
        let registry=try WorkflowStore.readBounded(policy,limit:1_048_576)
        guard let object=try JSONSerialization.jsonObject(with:registry) as? [String:Any],object["schema"] as? Int==1 else {throw RestoreError(.runtimeUnavailable,"Invalid droplet tag registry.")}
        try Task.checkCancellation()
        // A fresh bundle is assembled from fixed components, never copied with an
        // inherited signature or unreviewed additional executable resources.
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let resources=output.appendingPathComponent("Contents/Resources"),macOS=output.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:macOS,withIntermediateDirectories:true)
        let target=macOS.appendingPathComponent("RestoreGPSTimeDroplet")
        try FileManager.default.copyItem(at:executable,to:target)
        guard chmod(target.path,0o755)==0 else {throw RestoreError(.io,"Cannot mark the exported droplet executable.")}
        try registry.write(to:resources.appendingPathComponent("writable-tags.json"),options:.withoutOverwriting)
        try WorkflowStore().save(workflow,to:resources.appendingPathComponent("Workflow.rgtimeworkflow"))
        let identifier="io.github.delitants.RestoreGPSTime.droplet."+UUID().uuidString.lowercased()
        var info:[String:Any]=["CFBundleIdentifier":identifier,"CFBundleName":workflow.name,"CFBundleDisplayName":workflow.name,"CFBundleExecutable":"RestoreGPSTimeDroplet","CFBundlePackageType":"APPL","CFBundleShortVersionString":"1.0","CFBundleVersion":"1","LSMinimumSystemVersion":"13.0","LSUIElement":true,"NSHighResolutionCapable":true,"CFBundleDocumentTypes":[["CFBundleTypeName":"Photos, videos and folders","LSItemContentTypes":["public.item"],"CFBundleTypeRole":"Viewer","LSHandlerRank":"Alternate"]]]
        let icon=template.appendingPathComponent("Contents/Resources/AppIcon.icns")
        if SecureFS.exists(icon) {try WorkflowStore.readBounded(icon,limit:4_194_304).write(to:resources.appendingPathComponent("AppIcon.icns"),options:.withoutOverwriting);info["CFBundleIconFile"]="AppIcon"}
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:output.appendingPathComponent("Contents/Info.plist"),options:.withoutOverwriting)
        let environment=["PATH":"/usr/bin:/bin","LC_ALL":"C"]
        let signing=try await ProcessRunner().run(executable:URL(fileURLWithPath:"/usr/bin/codesign"),arguments:["--force","--sign","-","--identifier",identifier,"--options","runtime","--timestamp=none",output.path],environment:environment,timeout:30)
        guard signing.exitStatus==0 else {throw RestoreError(.verificationFailed,"Local droplet signing failed; the incomplete export is retained. "+String(decoding:signing.stderr,as:UTF8.self))}
        let verification=try await ProcessRunner().run(executable:URL(fileURLWithPath:"/usr/bin/codesign"),arguments:["--verify","--strict",output.path],environment:environment,timeout:30)
        guard verification.exitStatus==0 else {throw RestoreError(.verificationFailed,"The exported droplet signature did not verify; retain it for review.")}
        return .init(bundleURL:output,bundleIdentifier:identifier,signature:.adHocLocal)
    }
}
