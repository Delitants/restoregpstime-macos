import SwiftUI
import RestoreGPSTimeCore
struct DestinationView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:16) {
                Text("Save changes").font(.headline)
                Picker("Save mode",selection:$model.options.mode) {
                    Text("Save copies").tag(SaveMode.saveCopies)
                    Text("Change originals").tag(SaveMode.modifyInPlace)
                }.pickerStyle(.segmented).labelsHidden().frame(width:310).fixedSize(horizontal:true,vertical:false)
                Spacer(minLength:0)
            }
            if model.options.mode == .saveCopies {
                FolderChoice(title:"Save copies to",url:$model.options.outputRoot)
                Text("Your original files stay unchanged.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Originals are backed up before they change.",systemImage:"arrow.uturn.backward").font(.callout)
                Text("Use Backups & undo to restore a batch. Backups are kept on this Mac until you remove them.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Advanced backup settings") {
                    VStack(alignment:.leading,spacing:8) {
                        FolderChoice(title:"Originals backup",url:$model.options.recoveryRoot)
                        Text("This stores retained originals and undo records. It is separate from the destination for saved copies.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,8)
                }
            }
        }
    }
}
