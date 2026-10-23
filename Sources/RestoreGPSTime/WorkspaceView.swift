import SwiftUI
import UniformTypeIdentifiers
import RestoreGPSTimeCore

struct WorkspaceView:View {
    @ObservedObject var session:AppSession
    @ObservedObject var model:AppModel
    @State private var section:WorkspaceSection? = .dates
    @State private var selection:String?
    @State private var inspectorVisible=false
    @State private var dropTarget=false
    @State private var exportSheet=false
    @State private var includeCoordinates=false
    @State private var blockedReasonsVisible=false
    private var utility:Bool {section?.isUtility ?? false}
    var body:some View {
        VStack(spacing:0) {
            if session.incompleteRecoveryCount>0 || session.recoveryNotice != nil {
                HStack {
                    Label(session.recoveryNotice ?? "\(session.incompleteRecoveryCount) incomplete batches need review.",systemImage:"exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange).lineLimit(2)
                    Spacer();Button("Review backups") {section = .recovery}.fixedSize()
                }.padding(10)
                Divider()
            }
            HSplitView {
                SidebarView(section:$section)
                VStack(spacing:0) {
                    importBar
                    Divider()
                    if utility {
                        ScrollView {sectionView.padding(24).frame(maxWidth:860,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)}.disabled(model.isBusy)
                    } else {
                        VSplitView {
                            BatchTableView(model:model,selection:$selection).frame(minHeight:180)
                            optionsPanel.frame(minHeight:190,idealHeight:300,maxHeight:380)
                        }
                    }
                }.frame(minWidth:650)
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
                if !urls.isEmpty {_ = await session.openURLs(urls);section = .dates}
            }
            return true
        }
        .overlay {if dropTarget {RoundedRectangle(cornerRadius:8).stroke(Color.accentColor,lineWidth:3).allowsHitTesting(false)}}
        .onChange(of:model.phase) {value in if value == .finished {Task {await session.refreshRecovery()}}}
        .onChange(of:model.options.recoveryRoot) {_ in Task {await session.refreshRecovery()}}
        .onChange(of:model.discovery.includeFiles) {_ in refreshScope()}
        .onChange(of:model.discovery.recursive) {_ in refreshScope()}
        .onChange(of:model.discovery.includeFolders) {_ in refreshScope()}
        .onChange(of:model.discovery.includeHidden) {_ in refreshScope()}
        .sheet(isPresented:$importOptions) {
            VStack(alignment:.leading,spacing:16) {
                HStack {Text("Import options").font(.headline);Spacer();Button("Done") {importOptions=false}.fixedSize().keyboardShortcut(.cancelAction)}
                Toggle("Include files",isOn:$model.discovery.includeFiles).disabled(model.isBusy)
                Toggle("Include subfolders",isOn:$model.discovery.recursive).disabled(model.isBusy)
                Toggle("Include folders themselves",isOn:$model.discovery.includeFolders).disabled(model.isBusy)
                Toggle("Include hidden files",isOn:$model.discovery.includeHidden).disabled(model.isBusy)
                Text("Packages, symlinks, unavailable cloud files, and private transaction folders are excluded.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:440)
        }
        .sheet(isPresented:$inspectorVisible) {
            VStack(spacing:0) {
                HStack {Text("File details").font(.headline);Spacer();Button("Done") {inspectorVisible=false}.fixedSize().keyboardShortcut(.cancelAction)}.padding(16)
                Divider()
                InspectorView(model:model,row:model.rows.first {$0.id==selection}).disabled(model.isBusy)
            }.frame(width:600,height:640)
        }
        .sheet(isPresented:$exportSheet) {
            VStack(alignment:.leading,spacing:16) {
                Text("Export batch report").font(.title2.bold())
                Text("Save a local JSON or CSV report. File paths, selected changes, place names, errors, and recovery references are included.")
                Toggle("Include coordinate fields",isOn:$includeCoordinates)
                HStack {Button("Cancel") {exportSheet=false}.fixedSize().keyboardShortcut(.cancelAction);Spacer();Button("Choose File…") {Task {await export()}}.fixedSize().keyboardShortcut(.defaultAction)}
            }.padding(24).frame(width:460)
        }
        .sheet(isPresented:$blockedReasonsVisible) {
            VStack(alignment:.leading,spacing:16) {
                HStack {Text("Why files are blocked").font(.headline);Spacer();Button("Done") {blockedReasonsVisible=false}.fixedSize().keyboardShortcut(.cancelAction)}
                Text("Each reason counts affected asset groups. A group can have more than one reason. Blocked groups are skipped when you apply the eligible changes.").font(.callout)
                List(model.blockedReasons) {entry in
                    VStack(alignment:.leading,spacing:5) {
                        Text("\(entry.groupCount) \(entry.groupCount==1 ? "asset group":"asset groups")").font(.headline)
                        Text(entry.reason).textSelection(.enabled)
                    }.padding(.vertical,6)
                }
                Text("For dates without a UTC offset, set the camera’s time zone under Time zone and video settings. Dates with their own offset keep it. Preview again after changing settings.").font(.caption)
            }.padding(20).frame(width:580,height:460)
        }
    }
    private var importBar:some View {
        HStack(spacing:12) {
            Button {Task {let urls=await Panels.importFiles();if !urls.isEmpty {_ = await session.openURLs(urls);section = .dates}}} label:{Label("Add files",systemImage:"plus")}.fixedSize().keyboardShortcut("o").disabled(model.isBusy)
            Text("\(model.rows.count) \(model.rows.count == 1 ? "file":"files")").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if utility {Button("Back to batch") {section = .dates}.fixedSize()}
            else {Button {inspectorVisible=true} label:{Label("File details",systemImage:"info.circle")}.fixedSize().disabled(selection==nil).keyboardShortcut("i")}
            Menu("More") {
                Button("Refresh files") {Task {await model.importURLs([])}}.disabled(model.isBusy || model.rows.isEmpty)
                Button("Clear file list") {model.clear();selection=nil}.disabled(model.isBusy || model.rows.isEmpty)
                Divider()
                Button("Export report") {includeCoordinates=false;exportSheet=true}.disabled(model.report==nil || model.isBusy)
                Button("Import options") {importOptions.toggle()}
            }.fixedSize()
        }.padding(12)
    }
    @State private var importOptions=false
    private var optionsPanel:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                DestinationView(model:model)
                Divider()
                sectionView
            }.padding(20).frame(maxWidth:860,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
        }.disabled(model.isBusy)
    }
    @ViewBuilder private var sectionView:some View {
        switch section ?? .dates {
        case .dates:DateOptionsView(model:model).frame(maxWidth:650,alignment:.leading)
        case .places:PlaceOptionsView(model:model).frame(maxWidth:650,alignment:.leading)
        case .metadata:MetadataOptionsView(model:model).frame(maxWidth:650,alignment:.leading)
        case .finder:FinderOptionsView(model:model).frame(maxWidth:650,alignment:.leading)
        case .recovery:RecoveryView(model:model)
        case .workflows:WorkflowView(session:session,model:model)
        }
    }
    private var footer:some View {
        VStack(alignment:.leading,spacing:7) {
            if let preparation=model.preparationProgress,let total=preparation.total,total>0 {
                ProgressView(value:Double(preparation.completed),total:Double(total)).progressViewStyle(.linear).accessibilityLabel(preparation.message)
            }
            if !model.blockedReasons.isEmpty {
                Button("Review blocked reasons") {blockedReasonsVisible=true}.fixedSize()
            }
            if let issue=model.issue {ScrollView {Text(issue).font(.callout).foregroundStyle(.orange).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)}
            HStack(spacing:12) {
                if model.isBusy && model.preparationProgress?.total==nil {ProgressView().controlSize(.small)}
                Text(model.progress.isEmpty ? "Add files, choose settings, then preview.":model.progress).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                if model.isBusy {Button("Cancel") {model.cancel()}.fixedSize().disabled(model.phase == .recovering || model.phase == .cancelling)}
                if !utility {
                    Button("Preview changes") {Task {await model.preview()}}.fixedSize().disabled(model.rows.isEmpty || model.isBusy).keyboardShortcut("p",modifiers:[.command,.shift])
                    Button(model.options.mode == .saveCopies ? "Save copies":"Change originals") {Task {await model.applyPreview()}}.fixedSize().disabled(!model.canApply).buttonStyle(.borderedProminent)
                }
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
