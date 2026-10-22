import AppKit

@MainActor final class ServicesProvider:NSObject {
    private let route:([URL]) async -> ImportOutcome
    init(importer:DocumentImporter) {route={await importer.open(urls:$0)}}
    init(session:AppSession) {route={await session.openURLs($0)}}
    func importURLs(_ urls:[URL]) async -> ImportOutcome {await route(urls)}
    @objc func restoreMetadata(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls=(pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? (pasteboard.propertyList(forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String])?.map {URL(fileURLWithPath:$0)} ?? []
        guard !urls.isEmpty else {error.pointee="Select local photos, videos, or folders in Finder.";return}
        Task {
            NSApp.activate(ignoringOtherApps:true)
            let result=await importURLs(urls)
            if !result.errors.isEmpty {let alert=NSAlert();alert.messageText="RestoreGPSTime Import";alert.informativeText=result.errors.joined(separator:"\n");alert.runModal()}
        }
    }
}
