import SwiftUI
import RestoreGPSTimeCore
struct RecoveryView:View {
    @ObservedObject var model:AppModel
    @State private var batches=[RecoveryBatch]()
    @State private var issue:String?
    @State private var selection:UUID?
    @State private var files=Set<String>()
    @State private var confirm=false
    @State private var selectedOnly=false
    private let browser=RecoveryBrowser()
    private var selectedBatch:RecoveryBatch? {batches.first {$0.batchID==selection}}
    private var eligibleKeys:Set<String> {Set(selectedBatch?.files.filter(\.canUndo).map(\.sourceKey) ?? [])}
    private var selectedKeys:Set<String> {files.intersection(eligibleKeys)}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Backups & undo").font(.title2.bold())
            Text("Select a batch to undo all changes or choose individual files. Newer edits are protected.").foregroundStyle(.secondary)
            DisclosureGroup("Storage location") {FolderChoice(title:"Undo storage",url:$model.options.recoveryRoot).padding(.top,8)}
            HStack {Button("Refresh") {Task {await refresh()}};Spacer();Text("\(batches.count) saved batches").font(.caption)}
            if let issue {Text(issue).foregroundStyle(.orange).textSelection(.enabled)}
            List(batches,selection:$selection) {batch in
                VStack(alignment:.leading,spacing:4) {
                    Text(batch.createdAt.formatted()).font(.headline)
                    Text("\(batch.files.count) files • \(batch.phases.joined(separator:", "))").font(.caption)
                    if batch.incompleteGroups>0 {Text("\(batch.incompleteGroups) incomplete groups").foregroundStyle(.orange)}
                }.tag(batch.batchID)
            }.frame(minHeight:100,idealHeight:130,maxHeight:180)
            if let batch=selectedBatch {
                Text("Files in this batch").font(.headline)
                List(batch.files,selection:$files) {file in
                    HStack {
                        VStack(alignment:.leading,spacing:3) {Text(file.url.lastPathComponent);Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)}
                        Spacer()
                        Text(file.backupTitle+(file.canUndo ? "":" • Undo unavailable")).font(.caption).foregroundStyle(file.canUndo ? Color.secondary:Color.orange)
                    }.tag(file.sourceKey)
                }.frame(minHeight:100)
            }
            HStack {
                Button("Undo selected files…") {selectedOnly=true;confirm=true}.disabled(selectedKeys.isEmpty || model.isBusy)
                Button("Undo batch…") {selectedOnly=false;confirm=true}.disabled(eligibleKeys.isEmpty || model.isBusy)
                Button("Restore to folder…") {Task {
                    guard let id=selection,let folder=await Panels.folder(title:"Restore originals to a separate folder",create:true) else {return}
                    await model.restore(batchID:id,choice:.separateFolder(folder),selectedSourceKeys:selectedKeys.isEmpty ? nil:selectedKeys);await refresh()
                }}.disabled(eligibleKeys.isEmpty || model.isBusy)
            }.fixedSize(horizontal:true,vertical:false)
            Text("Metadata backups require the unchanged processed media to reconstruct originals. Linked photo and video files are restored together. Completed No backup batches cannot be undone.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .task {await refresh()}.onChange(of:model.options.recoveryRoot) {_ in Task {await refresh()}}.onChange(of:selection) {_ in files=[]}
        .confirmationDialog(selectedOnly ? "Undo selected files?":"Undo this batch?",isPresented:$confirm) {
            Button("Undo verified changes") {if let id=selection {let keys=selectedOnly ? selectedKeys:nil;Task {await model.restore(batchID:id,choice:.originalLocations,selectedSourceKeys:keys);await refresh()}}}
        } message:{Text("Current outputs must match their saved after-state. Linked files are restored together. Newer edits stay untouched.")}
    }
    private func refresh() async {
        guard let root=model.options.recoveryRoot else {batches=[];return}
        do {batches=try await browser.scan(root:root);issue=nil;if !batches.contains(where:{$0.batchID==selection}) {selection=nil;files=[]}}
        catch {batches=[];issue=error.localizedDescription}
    }
}
