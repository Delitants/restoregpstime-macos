import SwiftUI
import RestoreGPSTimeCore
struct DestinationView:View {
    @ObservedObject var model:AppModel
    private var backupDescription:String {
        switch model.options.effectiveBackupMode {
        case .metadata:return "A compact metadata database lets you undo each file. Keep the processed media: missing or damaged media needs a full backup."
        case .full:return "Entire original files are retained for undo, using more disk space."
        case .none:return "No retained backup or undo after successful changes."
        }
    }
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
                if model.options.outputRoot != nil {FolderChoice(title:"Save copies to",url:$model.options.outputRoot)}
                else {Text("Choose the output folder when you click Apply Changes. Preview works without one.").font(.callout).foregroundStyle(.secondary)}
                Text("Your original files stay unchanged.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Backup",selection:Binding(get:{model.options.effectiveBackupMode},set:{model.options.backupMode=$0})) {
                    Text("Metadata backup").tag(BackupMode.metadata)
                    Text("Full backup").tag(BackupMode.full)
                    Text("No backup").tag(BackupMode.none)
                }
                Text(backupDescription).font(.caption).foregroundStyle(model.options.effectiveBackupMode == .none ? .orange:.secondary).fixedSize(horizontal:false,vertical:true)
                DisclosureGroup("Advanced backup settings") {
                    VStack(alignment:.leading,spacing:8) {
                        FolderChoice(title:"Backup storage",url:$model.options.recoveryRoot)
                        Text("Metadata backup stores a compact per-file database. Full backup retains complete originals. Temporary working space is needed while applying or undoing changes.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,8)
                }
            }
        }
    }
}
