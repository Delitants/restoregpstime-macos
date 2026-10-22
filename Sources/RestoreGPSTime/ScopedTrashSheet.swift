import SwiftUI
import RestoreGPSTimeCore

struct ScopedTrashSheet:View {
    @ObservedObject var session:AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var roots=[URL]()
    @State private var recursive=false
    @State private var plan:TrashPlan?
    @State private var results=[TrashResult]()
    @State private var working=false
    @State private var issue:String?
    @State private var work:Task<Void,Never>?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Move Hidden Files to Trash").font(.title2.bold())
            Text("Choose the exact files or folders to inspect. Review the complete candidate list before moving anything to the system Trash. Output and recovery folders are excluded. Folders, packages and symbolic links are retained.").font(.callout)
            HStack {
                Button("Choose Scope…") {Task {let selected=await Panels.importFiles();if !selected.isEmpty {roots=selected;invalidate()}}}.disabled(working)
                Toggle("Include subfolders",isOn:$recursive).onChange(of:recursive) {_ in invalidate()}.disabled(working)
                Spacer()
                Button("Preview") {preview()}.disabled(working || roots.isEmpty)
            }
            Text(roots.map(\.path).joined(separator:"\n")).font(.caption).lineLimit(4).textSelection(.enabled)
            if let issue {Text(issue).foregroundStyle(.orange).textSelection(.enabled)}
            if let plan {
                Text("\(plan.candidates.count) hidden files; \(plan.excluded.count) exclusions").font(.headline)
                List {
                    ForEach(Array(plan.candidates.enumerated()),id:\.offset) {_,candidate in Text(candidate.snapshot.url.path).font(.caption).textSelection(.enabled)}
                    ForEach(Array(plan.excluded.enumerated()),id:\.offset) {_,entry in VStack(alignment:.leading) {Text(entry.url.path);Text(entry.reason).foregroundStyle(.secondary)}.font(.caption)}
                }.frame(minHeight:180)
            }
            if !results.isEmpty {
                Text("Results and recoverable Trash destinations").font(.headline)
                ScrollView {VStack(alignment:.leading,spacing:8) {ForEach(Array(results.enumerated()),id:\.offset) {_,result in
                    VStack(alignment:.leading) {Text(result.source.path);if let destination=result.trashedURL {Text("Trash: "+destination.path)};if let error=result.error {Text(error).foregroundStyle(.orange)}}.font(.caption).textSelection(.enabled)
                }}}.frame(maxHeight:160)
                Button("Export Local Receipt…") {Task {await exportReceipt()}}
            }
            HStack {
                Button(working ? "Cancel Remaining Work":"Close") {if working {work?.cancel()} else {dismiss()}}.keyboardShortcut(.cancelAction)
                if working {ProgressView().controlSize(.small)}
                Spacer()
                Button("Move \(plan?.candidates.count ?? 0) Files to Trash") {execute()}.disabled(working || session.model?.isBusy == true || plan?.candidates.isEmpty != false || !results.isEmpty)
            }
        }.padding(24).frame(width:720)
        .interactiveDismissDisabled(working)
    }
    private func invalidate() {plan=nil;results=[];issue=nil}
    private func preview() {
        working=true;session.scopedToolRunning=true;issue=nil;results=[]
        let excluded=[session.model?.options.outputRoot,session.model?.options.recoveryRoot].compactMap {$0}
        let scope=TrashScope(roots:roots,recursive:recursive,excludedRoots:excluded)
        work=Task {defer {working=false;session.scopedToolRunning=false;work=nil};do {plan=try await ScopedTrash().preview(scope:scope)} catch {plan=nil;issue=error.localizedDescription}}
    }
    private func execute() {
        guard let plan,session.model?.isBusy != true else {return};working=true;session.scopedToolRunning=true;issue=nil
        work=Task {defer {working=false;session.scopedToolRunning=false;work=nil};results=await ScopedTrash().execute(plan)}
    }
    private func exportReceipt() async {
        guard let url=await Panels.exportReport() else {return}
        do {let data=try JSONEncoder().encode(results);try await Task.detached {try data.write(to:url,options:.atomic)}.value} catch {issue=error.localizedDescription}
    }
}
