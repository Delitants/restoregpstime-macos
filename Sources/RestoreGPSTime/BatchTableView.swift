import SwiftUI

struct BatchTableView:View {
    @ObservedObject var model:AppModel
    @Binding var selection:String?
    @State private var sortOrder=[KeyPathComparator(\MediaRow.fileName)]
    var body:some View {
        Table(model.rows.sorted(using:sortOrder),selection:$selection,sortOrder:$sortOrder) {
            TableColumn("File",value:\.fileName) {row in
                HStack {Image(systemName:row.item?.snapshot.kind == .directory ? "folder":"doc").foregroundStyle(.secondary);Text(row.fileName).lineLimit(1)}.help(row.url.path)
            }.width(min:140,ideal:190)
            TableColumn("Current creation",value:\.creationText).width(min:145,ideal:165)
            TableColumn("Proposed creation",value:\.proposedCreationText).width(min:145,ideal:165)
            TableColumn("Proposed name",value:\.proposedName).width(min:140,ideal:190)
            TableColumn("Status",value:\.status) {row in
                Text(row.status).foregroundStyle(row.status=="blocked" || row.status=="failed" ? Color.orange:Color.secondary).help(row.issue ?? row.status)
            }.width(min:80,ideal:95)
        }.accessibilityLabel("Imported files and frozen proposed changes")
        .overlay {if model.rows.isEmpty {VStack(spacing:12) {Image(systemName:"photo.on.rectangle.angled").font(.system(size:38)).foregroundStyle(.secondary);Text("Add photos and videos").font(.title2);Text("Drop files or folders here, or choose Add Files.").foregroundStyle(.secondary)}}}
    }
}
extension MediaRow {
    var fileName:String {url.lastPathComponent}
    var creationText:String {displayDate(item?.snapshot.creationDate)}
    var proposedCreationText:String {displayDate(planned?.mutation.dates?.creationDate)}
    var proposedName:String {planned?.name.finalURL.lastPathComponent ?? "—"}
}
