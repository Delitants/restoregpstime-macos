import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RestoreGPSTimeCore

@MainActor enum Panels {
    static func importFiles() async -> [URL] {
        let panel=NSOpenPanel();panel.title="Add photos, videos, or folders";panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true
        return await panel.begin() == .OK ? panel.urls:[]
    }
    static func folder(title:String,create:Bool=false) async -> URL? {
        let panel=NSOpenPanel();panel.title=title;panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=create
        return await panel.begin() == .OK ? panel.url:nil
    }
    static func exportReport() async -> URL? {
        let panel=NSSavePanel();panel.title="Export local batch report";panel.nameFieldStringValue="RestoreGPSTime-report.json";panel.allowedContentTypes=[.json,.commaSeparatedText]
        return await panel.begin() == .OK ? panel.url:nil
    }
}
func displayDate(_ date:Date?,locale:Locale = .current,timeZone:TimeZone = .current)->String {
    guard let date else {return "—"}
    var style=Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.abbreviated)).minute(.twoDigits).second(.twoDigits).timeZone(.iso8601(.short))
    style.locale=locale;style.timeZone=timeZone
    return date.formatted(style)
}
extension Binding where Value == DatePolicy? {
    func field<T>(_ key:WritableKeyPath<DatePolicy,T>,default defaultValue:T)->Binding<T> {
        Binding<T>(get:{wrappedValue?[keyPath:key] ?? defaultValue},set:{value in var policy=wrappedValue ?? DatePolicy();policy[keyPath:key]=value;wrappedValue=policy})
    }
}
struct FolderChoice:View {
    let title:String
    @Binding var url:URL?
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {Text(title).font(.headline);Spacer();Button("Choose…") {Task {if let selected=await Panels.folder(title:title,create:true) {url=selected}}}}
            Text(url?.path ?? "Choose a folder").font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).help(url?.path ?? title)
        }
    }
}
