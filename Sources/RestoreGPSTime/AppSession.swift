import SwiftUI
import AppKit
import RestoreGPSTimeCore

@MainActor final class AppSession:ObservableObject {
    @Published var model:AppModel?
    @Published var runtimeIssue:String?
    @Published var runtimeDescription="Checking bundled metadata runtime…"
    @Published var finderTool:FinderTool?
    @Published var showScopedTrash=false
    @Published var scopedToolRunning=false
    @Published var toolResult:String?
    @Published var appearanceChoice=0 {didSet {if appearanceChoice != oldValue {persistPreferences()}}}
    @Published var incompleteRecoveryCount=0
    @Published var recoveryNotice:String?
    var appearance:ColorScheme? {appearanceChoice==1 ? .light:(appearanceChoice==2 ? .dark:nil)}
    let supportRoot:URL
    let finder:FinderVisibilityController
    private let preferences=AppPreferences()
    private var preferencesEnabled=false
    private var starting=false,pendingImports=[[URL]]()
    private var openQueue=[QueuedImport]()
    private var drainingImports=false
    private var importer:DocumentImporter?
    private var services:ServicesProvider?
    init(model:AppModel?=nil) {
        supportRoot=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RestoreGPSTime",isDirectory:true)
        finder=FinderVisibilityController(backend:SystemFinderVisibilityBackend(),recordURL:supportRoot.appendingPathComponent("finder-visibility.json"))
        self.model=model;if let model {importer=DocumentImporter(model:model,automaticRecoveryRoot:supportRoot.appendingPathComponent("Recovery",isDirectory:true))}
    }
    func start() async {
        guard !starting,model==nil else {return};starting=true;defer {starting=false};runtimeIssue=nil
        do {
            let paths=try RuntimeLocator().locate(in:Bundle.main.bundleURL)
            let identity=try await RuntimeProbe().inspect(paths:paths)
            let backend=LiveAppBackend(paths:paths),model=AppModel(backend:backend)
            model.options.recoveryRoot=supportRoot.appendingPathComponent("Recovery",isDirectory:true)
            do {
                if let saved=try preferences.load() {
                    model.request=saved.request;model.options=saved.options;model.discovery=saved.discovery;appearanceChoice=saved.appearance
                    if model.options.recoveryRoot==nil {model.options.recoveryRoot=supportRoot.appendingPathComponent("Recovery",isDirectory:true)}
                }
            } catch {model.presentError(RestoreError(.invalidInput,"Saved settings could not be loaded. Defaults are in use. "+error.localizedDescription))}
            model.settingsDidChange={[weak self] in self?.persistPreferences()}
            preferencesEnabled=true
            runtimeDescription="ExifTool \(identity.exifToolVersion) • Offline locations • \(identity.architecture)"
            self.model=model
            importer=DocumentImporter(model:model,automaticRecoveryRoot:supportRoot.appendingPathComponent("Recovery",isDirectory:true))
            let services=ServicesProvider(session:self);self.services=services;NSApp.servicesProvider=services
            await refreshRecovery()
            let imports=pendingImports;pendingImports=[]
            for urls in imports {_ = await openURLs(urls)}
        } catch {runtimeIssue=error.localizedDescription}
    }
    func persistPreferences() {
        guard preferencesEnabled,let model else {return}
        do {try preferences.save(request:model.request,options:model.options,discovery:model.discovery,appearance:appearanceChoice)}
        catch {model.presentError(RestoreError(.io,"Settings could not be saved: "+error.localizedDescription))}
    }
    func refreshRecovery() async {
        guard let root=model?.options.recoveryRoot else {incompleteRecoveryCount=0;return}
        do {incompleteRecoveryCount=try await RecoveryBrowser().scan(root:root).filter {$0.incompleteGroups>0}.count;recoveryNotice=nil}
        catch {recoveryNotice=error.localizedDescription}
    }
    func open(_ url:URL) async {_ = await openURLs([url])}
    func openURLs(_ urls:[URL]) async -> ImportOutcome {
        guard !scopedToolRunning else {return .init(errors:["Finish scoped Trash cleanup before importing another batch."])}
        guard importer != nil else {pendingImports.append(urls);return .init(errors:[])}
        guard openQueue.count<100 else {return .init(errors:["Too many pending imports. Finish this batch and open the remaining files again."])}
        return await withCheckedContinuation {continuation in
            openQueue.append(.init(urls:urls,continuation:continuation))
            if !drainingImports {drainingImports=true;Task {await drainImports()}}
        }
    }
    private func drainImports() async {
        while !openQueue.isEmpty {
            let next=openQueue.removeFirst()
            let result=await importer?.open(urls:next.urls) ?? ImportOutcome(errors:["The import runtime is unavailable."])
            if !result.errors.isEmpty {model?.presentError(RestoreError(.invalidInput,result.errors.joined(separator:"\n")))}
            next.continuation.resume(returning:result)
        }
        drainingImports=false
    }
    func prepareSupportFolder() async throws {
        let root=supportRoot
        try await Task.detached {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}.value
    }
    func exportDiagnostics() async {
        guard let url=await Panels.exportReport() else {return}
        let counts=model?.rows.reduce(into:[String:Int]()) {$0[$1.status,default:0]+=1} ?? [:]
        let object:[String:Any]=["application":"RestoreGPSTime","version":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development","runtime":runtimeDescription,"runtimeError":runtimeIssue ?? "","rowCounts":counts,"phase":String(describing:model?.phase),"automaticSharing":false]
        do {let data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]);try await Task.detached {try data.write(to:url,options:.atomic)}.value;toolResult="Diagnostics saved locally. No media metadata or coordinates were included."} catch {toolResult=error.localizedDescription}
    }
}

private struct QueuedImport {let urls:[URL],continuation:CheckedContinuation<ImportOutcome,Never>}
