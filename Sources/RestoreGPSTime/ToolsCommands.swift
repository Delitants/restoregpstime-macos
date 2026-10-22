import SwiftUI
import RestoreGPSTimeCore

enum FinderTool:String,Identifiable {case show="Show Hidden Files",hide="Hide Hidden Files",restore="Restore Previous Visibility";var id:String {rawValue}}
struct ToolsCommands:Commands {
    @ObservedObject var session:AppSession
    var body:some Commands {
        CommandMenu("Tools") {
            Button("Show Hidden Files…") {session.finderTool = .show}
            Button("Hide Hidden Files…") {session.finderTool = .hide}
            Button("Restore Previous Finder Visibility…") {session.finderTool = .restore}
            Divider()
            Button("Move Hidden Files to Trash…") {session.showScopedTrash=true}.disabled(session.model?.isBusy != false || session.scopedToolRunning)
            Divider()
            Button("Export Local Diagnostics…") {Task {await session.exportDiagnostics()}}
        }
        CommandGroup(after:.sidebar) {
            Picker("Appearance",selection:$session.appearanceChoice) {Text("System").tag(0);Text("Light").tag(1);Text("Dark").tag(2)}
        }
    }
}
struct FinderToolSheet:View {
    @ObservedObject var session:AppSession
    let tool:FinderTool
    @Environment(\.dismiss) private var dismiss
    @State private var preview:FinderVisibilityChange?
    @State private var issue:String?
    @State private var working=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(tool.rawValue).font(.title2.bold())
            Text("This changes Finder’s global hidden-file display preference for this account. The previous value is retained. Restarting Finder is a separate choice.")
            if let preview {Text("Current preference: \(String(describing:preview.previous))").font(.caption).textSelection(.enabled)}
            if let issue {Text(issue).foregroundStyle(.orange).textSelection(.enabled)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction).disabled(working)
                Spacer()
                Button("Apply") {Task {await apply(restart:false)}}.disabled(working || (tool != .restore && preview==nil))
                Button("Apply and Restart Finder") {Task {await apply(restart:true)}}.disabled(working || (tool != .restore && preview==nil))
            }
        }.padding(24).frame(width:520)
        .task {if tool != .restore {do {preview=try await session.finder.preview(visible:tool == .show)} catch {issue=error.localizedDescription}}}
    }
    private func apply(restart:Bool) async {
        working=true;defer {working=false}
        do {
            try await session.prepareSupportFolder()
            let result:FinderVisibilityResult
            if tool == .restore {result=try await session.finder.restorePrevious(restartApproved:restart)}
            else if let preview {result=try await session.finder.apply(preview,restartApproved:restart)} else {return}
            session.toolResult=result.note;dismiss()
        } catch {issue=error.localizedDescription}
    }
}
