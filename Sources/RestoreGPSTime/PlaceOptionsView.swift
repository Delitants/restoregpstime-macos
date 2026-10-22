import SwiftUI
import RestoreGPSTimeCore
struct PlaceOptionsView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Restore place names").font(.headline)
            Text("Coordinates are looked up in the bundled offline database. Results are nearby populated places, with approximate distance shown in the inspector.").font(.callout).foregroundStyle(.secondary)
            Toggle("Write place names to metadata",isOn:Binding(get:{model.request.location != nil},set:{model.request.location=$0 ? LocationWriteOptions():nil}))
            if let value=model.request.location {
                Toggle("Write a comment",isOn:Binding(get:{value.writeComment},set:{model.request.location?.writeComment=$0}))
                Toggle("Write structured city, region, country fields",isOn:Binding(get:{value.writeStructuredFields},set:{model.request.location?.writeStructuredFields=$0}))
                Picker("Comment destination",selection:Binding(get:{value.destination},set:{model.request.location?.destination=$0})) {
                    Text("Automatic for this format").tag(LocationCommentDestination.automatic);Text("EXIF UserComment").tag(LocationCommentDestination.exif);Text("XMP description").tag(LocationCommentDestination.xmp);Text("QuickTime description").tag(LocationCommentDestination.quickTime)
                }
                Picker("Existing comment",selection:Binding(get:{value.mode},set:{model.request.location?.mode=$0})) {Text("Append once").tag(CommentMode.appendOnce);Text("Replace").tag(CommentMode.replace)}
            }
            Divider()
            Toggle("Rename from place names",isOn:Binding(get:{!model.request.rename.preserveOriginal},set:{model.request.rename=$0 ? NameTemplate():.original}))
            if !model.request.rename.preserveOriginal {
                TextField("Filename template",text:Binding(get:{model.request.rename.pattern},set:{model.request.rename=NameTemplate($0)}))
                Text("Fields: {country}, {city}, {original}, {sequence:04}, {extension}. Keep .{extension} at the end. Matching places receive incremental numbers.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Select a file to review or correct its city and country. Corrections are marked manual. No coordinates leave this Mac.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
