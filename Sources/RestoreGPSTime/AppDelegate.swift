import AppKit

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    private weak var session:AppSession?
    private var pending=[[URL]]()
    func bind(_ session:AppSession) async {
        self.session=session
        let imports=pending;pending=[]
        for urls in imports {_ = await session.openURLs(urls)}
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        if let session {Task {_ = await session.openURLs(urls)}} else {pending.append(urls)}
    }
}
