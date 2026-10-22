import SwiftUI
import UniformTypeIdentifiers
import RestoreGPSTimeCore

struct WorkspaceView:View {
    @ObservedObject var session:AppSession
    @ObservedObject var model:AppModel
    @State private var section:WorkspaceSection? = .dates
    @State private var selection:String?
    @State private var inspectorVisible=true
    @State private var dropTarget=false
    @State private var exportSheet=false
    @State private var includeCoordinates=false
    var body:some View {
        VStack(spacing:0) {
            if session.incompleteRecoveryCount>0 || session.recoveryNotice != nil {
                HStack {
                    Label(session.recoveryNotice ?? "\(session.incompleteRecoveryCount) incomplete recovery batches need review.",systemImage:"exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange).lineLimit(2)
                    Spacer();Button("Review Recovery") {section = .recovery}
                }.padding(10)
                Divider()
            }
            HSplitView {
                SidebarView(section:$section)
                VStack(spacing:0) {
                    importBar
                    Divider()
                    BatchTableView(model:model,selection:$selection).frame(minHeight:180)
                    Divider()
                    optionsPanel.frame(minHeight:215,idealHeight:295,maxHeight:360)
                }.frame(minWidth:570)
                if inspectorVisible {InspectorView(model:model,row:model.rows.first {$0.id==selection}).disabled(model.isBusy)}
            }
            Divider()
            footer
        }
        .onDrop(of:[UTType.fileURL],isTargeted:$dropTarget) {providers in
            guard !model.isBusy else {return false}
            Task {
                var urls=[URL]()
                for provider in providers {
                    let url:URL?=await withCheckedContinuation {continuation in
                        provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) {value,_ in
                            if let url=value as? URL {continuation.resume(returning:url)}
                            else if let data=value as? Data {continuation.resume(returning:URL(dataRepresentation:data,relativeTo:nil))}
                            else {continuation.resume(returning:nil)}
                        }
                    }
                    if let url,url.isFileURL {urls.append(url)}
                }
                if !urls.isEmpty {_ = await session.openURLs(urls)}
            }
            return true
        }
        .overlay {if dropTarget {RoundedRectangle(cornerRadius:8).stroke(Color.accentColor,lineWidth:3).allowsHitTesting(false)}}
        .onChange(of:model.phase) {value in if value == .finished {Task {await session.refreshRecovery()}}}
        .onChange(of:model.options.recoveryRoot) {_ in Task {await session.refreshRecovery()}}
        .toolbar {
            ToolbarItem {Button {inspectorVisible.toggle()} label:{Label("Toggle Inspector",systemImage:"sidebar.right")}.help("Show or hide the file inspector")}
        }
        .sheet(isPresented:$exportSheet) {
            VStack(alignment:.leading,spacing:16) {
                Text("Export batch report").font(.title2.bold())
                Text("Save a local JSON or CSV report. File paths, selected changes, place names, errors, and recovery references are included.")
                Toggle("Include coordinate fields",isOn:$includeCoordinates)
                HStack {Button("Cancel") {exportSheet=false}.keyboardShortcut(.cancelAction);Spacer();Button("Choose File…") {Task {await export()}}.keyboardShortcut(.defaultAction)}
            }.padding(24).frame(width:460)
        }
    }
    private var importBar:some View {
        HStack(spacing:12) {
            Button {Task {_ = await session.openURLs(await Panels.importFiles())}} label:{Label("Add Files…",systemImage:"plus")}.keyboardShortcut("o").disabled(model.isBusy)
            Button("Refresh") {Task {await model.importURLs([])}}.disabled(model.isBusy || model.rows.isEmpty)
            Button("Clear") {model.clear();selection=nil}.disabled(model.isBusy || model.rows.isEmpty)
            Spacer()
            Text("\(model.rows.count) items").font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private var optionsPanel:some View {
        HSplitView {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    switch section ?? .dates {
                    case .dates:DateOptionsView(model:model)
                    case .places:PlaceOptionsView(model:model)
                    case .metadata:MetadataOptionsView(model:model)
                    case .finder:FinderOptionsView(model:model)
                    case .recovery:RecoveryView(model:model)
                    case .workflows:WorkflowView(session:session,model:model)
                    }
                }.padding(16)
            }.frame(minWidth:300).disabled(model.isBusy)
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    DestinationView(model:model)
                    DisclosureGroup("Import scope") {
                        VStack(alignment:.leading) {
                            Toggle("Include subfolders",isOn:$model.discovery.recursive)
                            Toggle("Include folders themselves",isOn:$model.discovery.includeFolders)
                            Toggle("Include hidden files",isOn:$model.discovery.includeHidden)
                            Text("Packages, symlinks, unavailable cloud files, and private transaction folders are excluded.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top,8)
                    }
                }.padding(16)
            }.frame(minWidth:250,idealWidth:290,maxWidth:360).disabled(model.isBusy)
        }
        .onChange(of:model.discovery.recursive) {_ in refreshScope()}
        .onChange(of:model.discovery.includeFolders) {_ in refreshScope()}
        .onChange(of:model.discovery.includeHidden) {_ in refreshScope()}
    }
    private var footer:some View {
        VStack(alignment:.leading,spacing:7) {
            if let issue=model.issue {ScrollView {Text(issue).font(.callout).foregroundStyle(.orange).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)}
            HStack(spacing:12) {
                if model.isBusy {ProgressView().controlSize(.small)}
                VStack(alignment:.leading,spacing:3) {Text(model.progress.isEmpty ? "Add files, choose options, then preview changes.":model.progress).lineLimit(2);Text(session.runtimeDescription).font(.caption).foregroundStyle(.secondary)}
                Spacer()
                Button("Export Report…") {includeCoordinates=false;exportSheet=true}.disabled(model.report==nil || model.isBusy)
                Button("Cancel") {model.cancel()}.disabled(!model.isBusy || model.phase == .recovering || model.phase == .cancelling)
                Button("Preview Changes") {Task {await model.preview()}}.disabled(model.rows.isEmpty || model.isBusy).keyboardShortcut("p",modifiers:[.command,.shift])
                Button(model.options.mode == .saveCopies ? "Save Copies":"Modify in Place") {Task {await model.applyPreview()}}.disabled(!model.canApply).buttonStyle(.borderedProminent)
            }
        }.padding(12)
    }
    private func refreshScope() {if !model.rows.isEmpty {Task {await model.importURLs([])}}}
    private func export() async {
        guard let report=model.report,let url=await Panels.exportReport() else {return}
        let coordinates=includeCoordinates
        do {try await Task.detached {try ReportExporter().export(report,to:url,includeCoordinates:coordinates)}.value;exportSheet=false} catch {model.presentError(error);exportSheet=false}
    }
}
