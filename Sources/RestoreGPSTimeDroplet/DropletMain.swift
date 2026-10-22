import AppKit
import RestoreGPSTimeCore

@main struct DropletMain {
    @MainActor static func main() {
        let app=NSApplication.shared,delegate=DropletDelegate()
        app.delegate=delegate;app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {app.run()}
    }
}
@MainActor final class DropletDelegate:NSObject,NSApplicationDelegate {
    private var pending=[URL](),launched=false,working=false
    func application(_ application:NSApplication,open urls:[URL]) {pending+=urls;if launched {Task {await handoff()}}}
    func applicationDidFinishLaunching(_ notification:Notification) {
        launched=true
        if pending.isEmpty {show("Drop photos, videos, or folders on this droplet.",detail:"The files open in RestoreGPSTime for destination selection and preview. No changes are applied silently.");NSApp.terminate(nil)}
        else {Task {await handoff()}}
    }
    private func handoff() async {
        guard !working,!pending.isEmpty else {return};working=true;defer {working=false}
        do {
            guard let main=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"io.github.delitants.RestoreGPSTime") else {throw RestoreError(.runtimeUnavailable,"Install RestoreGPSTime first, then open this droplet again. No input file was changed.")}
            let urls=pending;pending=[];let workflowURL=Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Workflow.rgtimeworkflow")
            let file=try await Task.detached {let workflow=try WorkflowStore().load(from:workflowURL);return try DropletHandoff(workflow:workflow,urls:urls).write()}.value
            let configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
            _ = try await NSWorkspace.shared.open([file],withApplicationAt:main,configuration:configuration)
            if !pending.isEmpty {working=false;await handoff()} else {NSApp.terminate(nil)}
        } catch {show("Could not open RestoreGPSTime",detail:error.localizedDescription);NSApp.terminate(nil)}
    }
    private func show(_ title:String,detail:String) {NSApp.activate(ignoringOtherApps:true);let alert=NSAlert();alert.messageText=title;alert.informativeText=detail;alert.runModal()}
}
