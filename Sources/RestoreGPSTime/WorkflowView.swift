import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RestoreGPSTimeCore

struct WorkflowView:View {
    @ObservedObject var session:AppSession
    @ObservedObject var model:AppModel
    @State private var name="Restore dates and places"
    @State private var message:String?
    @State private var working=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Saved workflows").font(.headline)
            TextField("Workflow name",text:$name)
            Text("Save the current date, place, metadata, and naming settings. Source files, per-file corrections, and destination or recovery paths are omitted.").font(.caption).foregroundStyle(.secondary)
            HStack {Button("Save Workflow…") {Task {await save()}};Button("Open Workflow…") {Task {await load()}};Button("Export Droplet…") {Task {await droplet()}}}.fixedSize(horizontal:true,vertical:false).disabled(working || model.isBusy)
            if working {ProgressView().controlSize(.small)}
            if let message {Text(message).font(.callout).textSelection(.enabled)}
            Divider()
            Text("A droplet sends dropped files and its workflow to the installed RestoreGPSTime app. You select destinations, preview, and apply there.").font(.callout)
            Text("Exported droplets are signed ad-hoc for local use. They are separate apps with new identities and do not inherit Developer ID signing or notarization. Keep Gatekeeper enabled.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func save() async {
        let panel=NSSavePanel();panel.title="Save workflow";panel.nameFieldStringValue="RestoreGPSTime.rgtimeworkflow";panel.allowedContentTypes=[UTType(filenameExtension:"rgtimeworkflow") ?? .data]
        guard await panel.begin() == .OK,let url=panel.url else {return}
        let document=WorkflowDocument(name:name,request:model.request);working=true;defer {working=false}
        do {try await Task.detached {try WorkflowStore().save(document,to:url)}.value;message="Workflow saved locally."} catch {message=error.localizedDescription}
    }
    private func load() async {
        let panel=NSOpenPanel();panel.title="Open a RestoreGPSTime workflow";panel.allowedContentTypes=[UTType(filenameExtension:"rgtimeworkflow") ?? .data]
        guard await panel.begin() == .OK,let url=panel.url else {return}
        working=true;defer {working=false}
        let result=await session.openURLs([url]);message=result.errors.isEmpty ? "Workflow loaded. Choose where to save copies, then preview. Undo storage is managed automatically.":result.errors.joined(separator:"\n")
    }
    private func droplet() async {
        let panel=NSSavePanel();panel.title="Export a local droplet";panel.nameFieldStringValue="RestoreGPSTime Workflow.app";panel.allowedContentTypes=[.applicationBundle]
        guard await panel.begin() == .OK,let url=panel.url else {return}
        let document=WorkflowDocument(name:name,request:model.request),template=Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/DropletTemplate.app")
        working=true;defer {working=false}
        do {let result=try await DropletExporter().export(workflow:document,to:url,template:template);message="Local droplet exported (\(result.signature.rawValue)). Move it freely; RestoreGPSTime must be installed to receive files."} catch {message=error.localizedDescription}
    }
}
