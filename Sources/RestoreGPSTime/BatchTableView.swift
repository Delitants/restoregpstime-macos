import SwiftUI
import AppKit

struct BatchTableView:View {
    @ObservedObject var model:AppModel
    @Binding var selection:String?
    @AppStorage("thumbnailSize") private var thumbnailPreference=ThumbnailSize.off.rawValue
    private var thumbnailSize:ThumbnailSize {ThumbnailSize(rawValue:thumbnailPreference) ?? .off}
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Spacer()
                Picker("Thumbnails",selection:Binding(get:{thumbnailSize.rawValue},set:{thumbnailPreference=$0})) {
                    ForEach(ThumbnailSize.allCases,id:\.rawValue) {size in Text(size.title).tag(size.rawValue)}
                }.pickerStyle(.menu).fixedSize().padding(.horizontal,8).padding(.vertical,4)
            }
            NativeBatchTable(rows:model.rows,selection:$selection,thumbnailSize:thumbnailSize)
                .accessibilityLabel("Imported files and frozen proposed changes")
                .overlay {
                    if model.rows.isEmpty {
                        VStack(spacing:12) {
                            Image(systemName:"photo.on.rectangle.angled").font(.system(size:38)).foregroundStyle(.secondary)
                            Text("Add photos and videos").font(.title2)
                            Text("Drop files or folders here, or choose Add Files.").foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }
        }
    }
}

private struct NativeBatchTable:NSViewRepresentable {
    let rows:[MediaRow]
    @Binding var selection:String?
    let thumbnailSize:ThumbnailSize
    func makeCoordinator()->Coordinator {Coordinator(selection:$selection)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView()
        scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        let table=PreviewTableView()
        table.headerView=NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors=true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection=false;table.allowsEmptySelection=true
        table.intercellSpacing=NSSize(width:0,height:1)
        for (key,title,width,minimum) in [("file","File",210.0,140.0),("current","Current creation",180.0,145.0),("creation","Proposed creation",180.0,145.0),("name","Proposed name",210.0,140.0),("status","Status",110.0,80.0)] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(key))
            column.title=title;column.width=width;column.minWidth=minimum
            column.resizingMask = .userResizingMask
            column.sortDescriptorPrototype=NSSortDescriptor(key:key,ascending:true,selector:#selector(NSString.localizedStandardCompare(_:)))
            if key == "creation" || key == "name" {column.headerCell=ProposedHeaderCell(textCell:title)}
            table.addTableColumn(column)
        }
        table.sortDescriptors=[NSSortDescriptor(key:"file",ascending:true)]
        table.dataSource=context.coordinator;table.delegate=context.coordinator
        scroll.documentView=table
        context.coordinator.table=table
        table.visibilityChanged={[weak coordinator=context.coordinator] in coordinator?.updateVisibleThumbnails()}
        scroll.contentView.postsBoundsChangedNotifications=true
        context.coordinator.boundsObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) {[weak coordinator=context.coordinator] _ in
            MainActor.assumeIsolated {coordinator?.updateVisibleThumbnails()}
        }
        context.coordinator.provider.onChange={[weak coordinator=context.coordinator] in coordinator?.refreshVisibleCells()}
        return scroll
    }
    func updateNSView(_ view:NSScrollView,context:Context) {
        context.coordinator.selection=$selection
        context.coordinator.update(rows:rows,size:thumbnailSize,selected:selection)
    }
    static func dismantleNSView(_ view:NSScrollView,coordinator:Coordinator) {
        coordinator.provider.setVisible([])
        if let observer=coordinator.boundsObserver {NotificationCenter.default.removeObserver(observer)}
        coordinator.boundsObserver=nil
    }

    @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
        weak var table:PreviewTableView?
        var selection:Binding<String?>
        var rows=[MediaRow](), signature=[String]()
        var size:ThumbnailSize = .off
        var boundsObserver:NSObjectProtocol?
        let provider=ThumbnailProvider()
        private var applyingSelection=false
        init(selection:Binding<String?>) {self.selection=selection}
        func update(rows:[MediaRow],size:ThumbnailSize,selected:String?) {
            guard let table else {return}
            applyingSelection=true
            let next=rows.map {[$0.id,$0.url.path,$0.creationText,$0.proposedCreationText,$0.proposedName,$0.status,$0.issue ?? "",$0.thumbnailRevision].joined(separator:"\u{0}")}
            if next != signature || self.size != size {
                signature=next;self.rows=rows;self.size=size
                sortRows();table.rowHeight=size.rowHeight;table.reloadData()
            }
            if let selected,let index=self.rows.firstIndex(where:{$0.id==selected}) {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
            else {table.deselectAll(nil)}
            applyingSelection=false
            refreshVisibleCells()
            updateVisibleThumbnails()
        }
        func numberOfRows(in tableView:NSTableView)->Int {rows.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            guard rows.indices.contains(row),let column=tableColumn else {return nil}
            let id=column.identifier
            let cell=(tableView.makeView(withIdentifier:id,owner:self) as? PreviewCell) ?? PreviewCell(identifier:id)
            configure(cell,row:row,key:id.rawValue)
            return cell
        }
        private func configure(_ cell:PreviewCell,row:Int,key:String) {
            let value=rows[row]
            let proposed=key == "creation" || key == "name"
            cell.isProposed=proposed
            cell.isSelected=table?.selectedRowIndexes.contains(row) == true
            cell.label.stringValue=text(value,key:key)
            cell.label.textColor=proposed ? ProposedColors.text:(cell.isSelected ? .alternateSelectedControlTextColor:(key == "status" && ["blocked","failed"].contains(value.status) ? .systemOrange:.labelColor))
            cell.toolTip=key == "file" ? value.url.path:(key == "status" ? value.issue ?? value.status:cell.label.stringValue)
            if key == "file" {
                let placeholder=NSImage(systemSymbolName:value.item?.snapshot.kind == .directory ? "folder":"doc",accessibilityDescription:nil)
                cell.setImage(size == .off ? placeholder:request(for:value).flatMap {provider.cachedResult(for:$0)?.image} ?? placeholder,points:size == .off ? 16:size.points)
            } else {cell.setImage(nil,points:0)}
            cell.needsDisplay=true
        }
        private func text(_ row:MediaRow,key:String)->String {
            switch key {case "file":return row.fileName;case "current":return row.creationText;case "creation":return row.proposedCreationText;case "name":return row.proposedName;default:return row.status}
        }
        private func sortRows() {
            let descriptors=table?.sortDescriptors ?? []
            rows.sort {left,right in
                for descriptor in descriptors {
                    let a=text(left,key:descriptor.key ?? "file"),b=text(right,key:descriptor.key ?? "file")
                    let comparison=a.localizedStandardCompare(b)
                    if comparison != .orderedSame {return descriptor.ascending ? comparison == .orderedAscending:comparison == .orderedDescending}
                }
                return left.id < right.id
            }
        }
        func tableView(_ tableView:NSTableView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]) {
            let selected=selection.wrappedValue
            applyingSelection=true
            sortRows();tableView.reloadData()
            if let selected,let index=rows.firstIndex(where:{$0.id==selected}) {tableView.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
            applyingSelection=false
            refreshVisibleCells()
            updateVisibleThumbnails()
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !applyingSelection,let table else {return}
            selection.wrappedValue=rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id:nil
            refreshVisibleCells()
        }
        private func request(for row:MediaRow)->ThumbnailRequest? {
            guard size != .off,row.item?.snapshot.kind != .directory else {return nil}
            return ThumbnailRequest(url:row.url,size:size,revision:row.thumbnailRevision)
        }
        func updateVisibleThumbnails() {
            guard let table,table.window != nil,!table.isHiddenOrHasHiddenAncestor,size != .off else {provider.setVisible([]);return}
            let range=table.rows(in:table.visibleRect)
            guard range.location != NSNotFound,range.length>0 else {provider.setVisible([]);return}
            let end=min(rows.count,range.location+range.length)
            provider.setVisible((range.location..<end).compactMap {request(for:rows[$0])})
        }
        func refreshVisibleCells() {
            guard let table else {return}
            let range=table.rows(in:table.visibleRect)
            guard range.location != NSNotFound,range.length>0 else {return}
            for row in range.location..<min(rows.count,range.location+range.length) {
                for column in table.tableColumns.indices {
                    if let cell=table.view(atColumn:column,row:row,makeIfNecessary:false) as? PreviewCell {configure(cell,row:row,key:table.tableColumns[column].identifier.rawValue)}
                }
            }
        }
    }
}

private final class PreviewTableView:NSTableView {
    var visibilityChanged:(()->Void)?
    override func layout() {super.layout();visibilityChanged?()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();visibilityChanged?()}
    override func viewDidHide() {super.viewDidHide();visibilityChanged?()}
    override func viewDidUnhide() {super.viewDidUnhide();visibilityChanged?()}
}
private enum ProposedColors {
    static let fill=NSColor(calibratedRed:0.83,green:0.95,blue:0.82,alpha:1)
    static let selected=NSColor(calibratedRed:0.63,green:0.84,blue:0.64,alpha:1)
    static let text=NSColor(calibratedWhite:0.12,alpha:1)
}
private final class ProposedHeaderCell:NSTableHeaderCell {
    override func draw(withFrame cellFrame:NSRect,in controlView:NSView) {
        ProposedColors.fill.setFill();cellFrame.fill()
        let titleRect=cellFrame.insetBy(dx:6,dy:2)
        attributedStringValue=NSAttributedString(string:stringValue,attributes:[.foregroundColor:ProposedColors.text,.font:NSFont.systemFont(ofSize:NSFont.smallSystemFontSize,weight:.medium)])
        super.drawInterior(withFrame:titleRect,in:controlView)
        NSColor.separatorColor.setFill();NSRect(x:cellFrame.maxX-1,y:cellFrame.minY,width:1,height:cellFrame.height).fill()
    }
    override func drawSortIndicator(withFrame cellFrame:NSRect,in controlView:NSView,ascending:Bool,priority:Int) {
        let center=NSPoint(x:cellFrame.midX,y:cellFrame.midY)
        let arrow=NSBezierPath()
        arrow.move(to:NSPoint(x:center.x-3,y:center.y+(ascending ? 2:-2)))
        arrow.line(to:NSPoint(x:center.x,y:center.y+(ascending ? -2:2)))
        arrow.line(to:NSPoint(x:center.x+3,y:center.y+(ascending ? 2:-2)))
        ProposedColors.text.setStroke();arrow.lineWidth=1.5;arrow.stroke()
    }
}
private final class PreviewCell:NSView {
    let label=NSTextField(labelWithString:"")
    private let thumbnail=NSImageView()
    private var imagePoints:CGFloat=0
    var isProposed=false,isSelected=false
    init(identifier:NSUserInterfaceItemIdentifier) {
        super.init(frame:.zero);self.identifier=identifier
        label.lineBreakMode = .byTruncatingTail;label.maximumNumberOfLines=1
        label.font = .systemFont(ofSize:NSFont.systemFontSize)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        addSubview(thumbnail);addSubview(label)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
    func setImage(_ image:NSImage?,points:CGFloat) {thumbnail.image=image;imagePoints=points;thumbnail.isHidden=points==0;needsLayout=true}
    override func layout() {
        super.layout()
        thumbnail.frame=NSRect(x:6,y:(bounds.height-imagePoints)/2,width:imagePoints,height:imagePoints)
        let start:CGFloat=imagePoints>0 ? imagePoints+14:6
        let height=label.intrinsicContentSize.height
        label.frame=NSRect(x:start,y:(bounds.height-height)/2,width:max(0,bounds.width-start-6),height:height)
    }
    override func draw(_ dirtyRect:NSRect) {
        if isProposed {
            (isSelected ? ProposedColors.selected:ProposedColors.fill).setFill();bounds.fill()
            if isSelected {NSColor.keyboardFocusIndicatorColor.setStroke();let border=NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke()}
        }
    }
}
extension MediaRow {
    fileprivate var thumbnailRevision:String {
        guard let snapshot=item?.snapshot else {return id}
        return "\(id):\(snapshot.id.size):\(snapshot.id.modified.timeIntervalSince1970):\(snapshot.id.changed.timeIntervalSince1970)"
    }
    var fileName:String {url.lastPathComponent}
    var creationText:String {displayDate(item?.snapshot.creationDate)}
    var proposedCreationText:String {displayDate(planned?.mutation.dates?.creationDate)}
    var proposedName:String {planned?.name.finalURL.lastPathComponent ?? "—"}
}
