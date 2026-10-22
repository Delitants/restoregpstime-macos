import SwiftUI
import AppKit
import RestoreGPSTimeCore

@MainActor final class AppSession:ObservableObject {
    @Published var model:AppModel?
    @Published var runtimeIssue:String?
    @Published var runtimeDescription="Checking bundled metadata runtime…"
    @Published var finderTool:FinderTool?
    @Published var toolResult:String?
    @Published var appearanceChoice=0
    @Published var incompleteRecoveryCount=0
    @Published var recoveryNotice:String?
    var appearance:ColorScheme? {appearanceChoice==1 ? .light:(appearanceChoice==2 ? .dark:nil)}
    let supportRoot:URL
    let finder:FinderVisibilityController
    private var starting=false,pendingURLs=[URL]()
    init() {
        supportRoot=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RestoreGPSTime",isDirectory:true)
        finder=FinderVisibilityController(backend:SystemFinderVisibilityBackend(),recordURL:supportRoot.appendingPathComponent("finder-visibility.json"))
    }
    func start() async {
        guard !starting,model==nil else {return};starting=true;defer {starting=false};runtimeIssue=nil
        do {
            let paths=try RuntimeLocator().locate(in:Bundle.main.bundleURL)
            let identity=try await RuntimeProbe().inspect(paths:paths)
            let backend=LiveAppBackend(paths:paths),model=AppModel(backend:backend)
            model.options.recoveryRoot=supportRoot.appendingPathComponent("Recovery",isDirectory:true)
            runtimeDescription="ExifTool \(identity.exifToolVersion) • Offline locations • \(identity.architecture)"
            self.model=model
            await refreshRecovery()
            if !pendingURLs.isEmpty {let urls=pendingURLs;pendingURLs=[];await model.importURLs(urls)}
        } catch {runtimeIssue=error.localizedDescription}
    }
    func refreshRecovery() async {
        guard let root=model?.options.recoveryRoot else {incompleteRecoveryCount=0;return}
        do {incompleteRecoveryCount=try await RecoveryBrowser().scan(root:root).filter {$0.incompleteGroups>0}.count;recoveryNotice=nil}
        catch {recoveryNotice=error.localizedDescription}
    }
    func open(_ url:URL) async {if let model {await model.importURLs([url])} else {pendingURLs.append(url)}}
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
