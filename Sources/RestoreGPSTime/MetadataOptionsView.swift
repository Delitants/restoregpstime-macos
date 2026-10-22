import SwiftUI
import RestoreGPSTimeCore
struct MetadataOptionsView:View {
    @ObservedObject var model:AppModel
    @State private var tag="XMP-dc:Description-x-default"
    @State private var value=""
    @State private var remove=false
    @State private var validation:String?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Metadata").font(.headline)
            Picker("Write destination",selection:$model.request.metadataDestination) {Text("Embedded metadata").tag(MetadataDestination.embedded);Text("New XMP sidecar").tag(MetadataDestination.xmpSidecar)}
            Toggle("Remove recognized GPS metadata",isOn:$model.request.removeGPS)
            Toggle("Strip supported descriptive metadata",isOn:$model.request.stripMetadata)
            Text("Removal is limited by the verified container profile. Rendering data, color profiles, orientation, and linked asset identifiers are protected. Unsupported variants are blocked.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Explicit tag changes").font(.headline)
            TextField("Qualified Group:Tag",text:$tag)
            Toggle("Remove this tag",isOn:$remove)
            if !remove {TextField("Literal text value",text:$value,axis:.vertical).lineLimit(2...5)}
            Button("Add Tag Change") {
                guard let id=TagID(rawValue:tag) else {validation="Enter a qualified Group:Tag name.";return}
                model.request.tags.append(remove ? .remove(id):.set(id,.string(value)));validation=nil
            }
            if let validation {Text(validation).foregroundStyle(.orange)}
            ForEach(Array(model.request.tags.enumerated()),id:\.offset) {index,mutation in
                HStack(alignment:.top) {Text(String(describing:mutation)).font(.caption).textSelection(.enabled);Spacer();Button {model.request.tags.remove(at:index)} label:{Image(systemName:"minus.circle")}.accessibilityLabel("Remove tag change \(index+1)")}
            }
            Text("Preview validates tag names and typed values against the bundled writable-tag registry. It shows each actual destination before applying.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
