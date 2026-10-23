import Foundation
import RestoreGPSTimeCore

struct ImportOutcome:Sendable {let errors:[String]}
private struct PreparedImport:Sendable {let workflow:WorkflowDocument?,urls:[URL],replaceBatch:Bool}
@MainActor final class DocumentImporter {
    let model:AppModel
    private let automaticRecoveryRoot:URL?
    private var importing=false
    init(model:AppModel,automaticRecoveryRoot:URL?=nil) {self.model=model;self.automaticRecoveryRoot=automaticRecoveryRoot}
    func open(urls:[URL]) async -> ImportOutcome {
        guard !model.isBusy,!importing else {return .init(errors:["Finish or cancel the current operation before opening another import."])}
        guard !urls.isEmpty else {return .init(errors:[])}
        importing=true;defer {importing=false}
        do {
            let prepared=try await Task.detached {try Self.prepare(urls)}.value
            guard !model.isBusy else {return .init(errors:["The batch started while reading the import. Finish it before opening these files."])}
            if prepared.replaceBatch {model.clear()}
            if let workflow=prepared.workflow {
                model.request=workflow.request
                var options=BatchOptions();options.backupMode = .metadata;options.importRoots=model.options.importRoots;options.recoveryRoot=automaticRecoveryRoot;model.options=options
            }
            if !prepared.urls.isEmpty {await model.importURLs(prepared.urls)}
            if !model.rows.isEmpty {await model.preview(component:model.activePreviewComponent)}
            return .init(errors:[])
        } catch {model.presentError(error);return .init(errors:[error.localizedDescription])}
    }
    private nonisolated static func prepare(_ urls:[URL]) throws -> PreparedImport {
        guard urls.count<=10_000,urls.allSatisfy(\.isFileURL) else {throw RestoreError(.invalidInput,"Import a bounded list of local files.")}
        let handoffs=urls.filter {$0.pathExtension.lowercased()=="rgtimehandoff"}
        if !handoffs.isEmpty {
            guard handoffs.count==1,urls.count==1 else {throw RestoreError(.conflict,"Open one droplet handoff at a time.")}
            let value=try DropletHandoff.load(from:handoffs[0])
            return .init(workflow:value.workflow,urls:value.urls,replaceBatch:true)
        }
        let workflows=urls.filter {$0.pathExtension.lowercased()=="rgtimeworkflow"}
        guard workflows.count<=1 else {throw RestoreError(.conflict,"Choose one workflow for a batch.")}
        let workflow=try workflows.first.map {try WorkflowStore().load(from:$0)}
        return .init(workflow:workflow,urls:urls.filter {$0.pathExtension.lowercased() != "rgtimeworkflow"},replaceBatch:false)
    }
}
