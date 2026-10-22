import SwiftUI
import RestoreGPSTimeCore
struct DestinationView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Save mode",selection:$model.options.mode) {Text("Save Copies").tag(SaveMode.saveCopies);Text("Modify in Place").tag(SaveMode.modifyInPlace)}.pickerStyle(.segmented)
            if model.options.mode == .saveCopies {FolderChoice(title:"Output folder",url:$model.options.outputRoot)}
            else {Text("Each original is verified and retained before its group changes. Review the preview before applying.").font(.caption).foregroundStyle(.secondary)}
            FolderChoice(title:"Recovery folder",url:$model.options.recoveryRoot)
            Text("Required backup and staging space is checked before processing. Existing files are never overwritten.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
