import SwiftUI

enum WorkspaceSection:String,CaseIterable,Identifiable {
    case dates="Restore Dates",places="Restore Places",metadata="Metadata",finder="Finder Attributes",workflows="Saved Workflows",recovery="Recovery"
    var id:Self {self}
    var symbol:String {switch self {case .dates:return "clock.arrow.circlepath";case .places:return "mappin.and.ellipse";case .metadata:return "tag";case .finder:return "folder.badge.gearshape";case .workflows:return "square.stack";case .recovery:return "arrow.uturn.backward"}}
}
struct SidebarView:View {
    @Binding var section:WorkspaceSection?
    var body:some View {
        List(WorkspaceSection.allCases,selection:$section) {value in Label(value.rawValue,systemImage:value.symbol).tag(value)}
            .listStyle(.sidebar).frame(minWidth:170,idealWidth:180,maxWidth:210)
            .accessibilityLabel("Workflow categories")
    }
}
