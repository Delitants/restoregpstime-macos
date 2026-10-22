import SwiftUI

enum WorkspaceSection:String,CaseIterable,Identifiable {
    case dates="Dates & time",places="Location names",metadata="Metadata",finder="Finder attributes",workflows="Workflows",recovery="Backups & undo"
    var id:Self {self}
    var symbol:String {switch self {case .dates:return "clock.arrow.circlepath";case .places:return "mappin.and.ellipse";case .metadata:return "tag";case .finder:return "folder.badge.gearshape";case .workflows:return "square.stack";case .recovery:return "arrow.uturn.backward"}}
    var isUtility:Bool {self == .workflows || self == .recovery}
}
struct SidebarView:View {
    @Binding var section:WorkspaceSection?
    @State private var moreTools=false
    var body:some View {
        List(selection:$section) {
            ForEach([WorkspaceSection.dates,.places]) {value in navigation(value)}
            DisclosureGroup("More tools",isExpanded:$moreTools) {
                ForEach([WorkspaceSection.metadata,.finder,.workflows,.recovery]) {value in navigation(value)}
            }.padding(.top,12)
        }
        .listStyle(.sidebar).frame(width:190)
        .accessibilityLabel("Workflow categories")
        .onChange(of:section) {value in if let value,![WorkspaceSection.dates,.places].contains(value) {moreTools=true}}
    }
    private func navigation(_ value:WorkspaceSection)->some View {
        Label(value.rawValue,systemImage:value.symbol).font(.system(size:13)).fixedSize(horizontal:true,vertical:false).tag(value)
    }
}
