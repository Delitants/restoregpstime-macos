import SwiftUI
import RestoreGPSTimeCore
struct RecoveryView:View {
    @ObservedObject var model:AppModel
    @State private var batches=[RecoveryBatch]()
    @State private var issue:String?
    @State private var selection:UUID?
    @State private var confirm=false
    private let browser=RecoveryBrowser()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Backups & undo").font(.title2.bold())
            Text("Restore originals from an in-place batch, or undo saved copies. Newer edits are always protected.").foregroundStyle(.secondary)
            DisclosureGroup("Storage location") {
                FolderChoice(title:"Undo storage",url:$model.options.recoveryRoot).padding(.top,8)
            }
            Text("Originals remain until you remove them yourself. Incomplete batches are listed first for review; nothing is restored automatically.").font(.caption).foregroundStyle(.secondary)
            HStack {Button("Refresh") {Task {await refresh()}};Spacer();Text("\(batches.count) saved batches").font(.caption)}
            if let issue {Text(issue).foregroundStyle(.orange).textSelection(.enabled)}
            List(batches,selection:$selection) {batch in
                VStack(alignment:.leading,spacing:4) {Text(batch.createdAt.formatted()).font(.headline);Text(batch.batchID.uuidString).font(.caption.monospaced());Text("\(batch.groups) groups • \(batch.phases.joined(separator:", "))").font(.caption);if batch.incompleteGroups>0 {Text("\(batch.incompleteGroups) incomplete groups").foregroundStyle(.orange)}}.tag(batch.batchID)
            }.frame(minHeight:130)
            HStack {
                Button("Undo batch…") {confirm=true}.disabled(selection==nil || model.isBusy)
                Button("Restore backups to folder…") {Task {guard let id=selection,let folder=await Panels.folder(title:"Restore retained originals to a separate folder",create:true) else {return};await model.restore(batchID:id,choice:.separateFolder(folder));await refresh()}}.disabled(selection==nil || model.isBusy)
            }.fixedSize(horizontal:true,vertical:false)
            Text("Undo restores retained originals or removes unchanged saved copies. Restore to a folder uses the originals retained by in-place batches. Newer edits are left untouched.").font(.caption).foregroundStyle(.secondary)
        }
        .task {await refresh()}.onChange(of:model.options.recoveryRoot) {_ in Task {await refresh()}}
        .confirmationDialog("Undo this batch?",isPresented:$confirm) {Button("Undo verified changes") {if let id=selection {Task {await model.restore(batchID:id,choice:.originalLocations);await refresh()}}}} message:{Text("Current outputs must match their saved after-state. Newer edits remain untouched and conflicts stay available for review.")}
    }
    private func refresh() async {
        guard let root=model.options.recoveryRoot else {batches=[];return}
        do {batches=try await browser.scan(root:root);issue=nil}
        catch {batches=[];issue=error.localizedDescription}
    }
}
