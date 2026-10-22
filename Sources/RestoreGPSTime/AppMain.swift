import SwiftUI
import RestoreGPSTimeCore

@main
struct RestoreGPSTimeApp:App {
    @StateObject private var session=AppSession()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body:some Scene {
        WindowGroup("RestoreGPSTime") {
            Group {
                if let model=session.model {WorkspaceView(session:session,model:model)}
                else {
                    VStack(spacing:18) {
                        Image(systemName:"clock.arrow.circlepath").font(.system(size:48)).foregroundStyle(.blue)
                        Text("RestoreGPSTime").font(.largeTitle.bold())
                        Text("Photo and video dates. Place names. Your files, restored.").foregroundStyle(.secondary)
                        if let issue=session.runtimeIssue {
                            Text("The bundled metadata runtime is unavailable.").font(.headline)
                            Text(issue).textSelection(.enabled).frame(maxWidth:640)
                            Button("Retry Runtime Check") {Task {await session.start()}}
                        } else {ProgressView();Text(session.runtimeDescription)}
                    }.padding(40).frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
            .frame(minWidth:1100,minHeight:720)
            .preferredColorScheme(session.appearance)
            .task {await appDelegate.bind(session);await session.start()}
            .sheet(isPresented:$session.showScopedTrash) {ScopedTrashSheet(session:session)}
            .sheet(item:$session.finderTool) {tool in FinderToolSheet(session:session,tool:tool)}
            .alert("Tools",isPresented:Binding(get:{session.toolResult != nil},set:{if !$0 {session.toolResult=nil}})) {Button("OK") {session.toolResult=nil}} message:{Text(session.toolResult ?? "")}
        }.defaultSize(width:1100,height:720)
        .commands {ToolsCommands(session:session)}
    }
}
