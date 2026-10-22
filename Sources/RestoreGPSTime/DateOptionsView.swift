import SwiftUI
import RestoreGPSTimeCore

struct DateOptionsView:View {
    @ObservedObject var model:AppModel
    private var enabled:Binding<Bool> {Binding(get:{model.request.dates != nil},set:{model.request.dates=$0 ? DatePolicy():nil})}
    private var policy:DatePolicy {model.request.dates ?? DatePolicy()}
    private var sourceName:String {
        switch policy.source {case .automaticCapture:return "Capture metadata";case .fileCreation:return "File creation";case .fileModification:return "File modification";case .specific:return "Specific date";case .current:return "Current time";case .filename:return "Filename pattern";case .referenceFile:return "Reference file";case .spotlight:return "Spotlight field";case .tag:return "Qualified metadata tag";case .reset:return "Reset to 1904"}
    }
    private let sources=["Capture metadata","File creation","File modification","Specific date","Current time","Filename pattern","Reference file","Spotlight field","Qualified metadata tag","Reset to 1904"]
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Toggle("Restore dates and times",isOn:enabled).font(.headline)
            if enabled.wrappedValue {
                Picker("Source",selection:Binding(get:{sourceName},set:{value in
                    var date=policy
                    switch value {case "File creation":date.source = .fileCreation;case "File modification":date.source = .fileModification;case "Specific date":date.source = .specific(Date());case "Current time":date.source = .current;case "Filename pattern":date.source = .filename("yyyyMMdd_HHmmss");case "Reference file":date.source = .referenceFile(.creation);case "Spotlight field":date.source = .spotlight("kMDItemContentCreationDate");case "Qualified metadata tag":date.source = .tag("ExifIFD:DateTimeOriginal");case "Reset to 1904":date.source = .reset;default:date.source = .automaticCapture}
                    model.request.dates=date
                })) {ForEach(sources,id:\.self) {Text($0)}}
                sourceDetails
                TextField("Missing time zone (e.g. Europe/Paris)",text:Binding(get:{policy.timeZoneID ?? ""},set:{model.request.dates?.timeZoneID=$0.isEmpty ? nil:$0}))
                    .help("Used only when a source has no explicit offset. Leave blank to block ambiguous local dates.")
                Picker("QuickTime integer dates",selection:$model.request.dates.field(\.quickTime,default:nil)) {
                    Text("Require a choice").tag(Optional<QuickTimeInterpretation>.none)
                    Text("Interpret as UTC").tag(Optional(QuickTimeInterpretation.utc))
                    Text("Camera local time in selected zone").tag(Optional(QuickTimeInterpretation.cameraLocal))
                }
                Picker("Repeated local hour (DST)",selection:$model.request.dates.field(\.dstChoice,default:nil)) {
                    Text("Require a choice").tag(Optional<DSTChoice>.none);Text("Earlier occurrence").tag(Optional(DSTChoice.earlier));Text("Later occurrence").tag(Optional(DSTChoice.later))
                }
                HStack {target("Creation",.creation);target("Modification",.modification);target("Capture tags",.capture)}
                DisclosureGroup("Shift, sequence, and removal") {
                    VStack(alignment:.leading,spacing:10) {
                        TextField("Shift (seconds)",value:$model.request.dates.field(\.shiftSeconds,default:0),format:.number)
                        Toggle("Shift each original file date independently",isOn:$model.request.dates.field(\.shiftOriginalTargets,default:false))
                        Toggle("Assign a sequence",isOn:Binding(get:{policy.sequenceStart != nil},set:{model.request.dates?.sequenceStart=$0 ? Date():nil}))
                        if let start=policy.sequenceStart {
                            DatePicker("Sequence start",selection:Binding(get:{start},set:{model.request.dates?.sequenceStart=$0}))
                            TextField("Step (seconds)",value:$model.request.dates.field(\.sequenceStepSeconds,default:0),format:.number)
                        }
                        Toggle("Remove selected embedded capture date tags",isOn:$model.request.dates.field(\.removeEmbeddedDates,default:false))
                        Toggle("Normalize a later creation / earlier modification pair",isOn:$model.request.dates.field(\.normalizeCompanionDate,default:false))
                    }.padding(.top,8)
                }
                Text("Embedded offsets take priority. Missing dates, nonexistent local times, and unresolved ambiguities block the affected group.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var sourceDetails:some View {
        switch policy.source {
        case .specific(let value):DatePicker("Date and time",selection:Binding(get:{value},set:{model.request.dates?.source = .specific($0)}))
        case .filename(let pattern):TextField("Pattern",text:Binding(get:{pattern},set:{model.request.dates?.source = .filename($0)}))
        case .tag(let key):TextField("Group:Tag",text:Binding(get:{key},set:{model.request.dates?.source = .tag($0)}))
        case .spotlight(let key):Picker("Existing Spotlight value",selection:Binding(get:{key},set:{model.request.dates?.source = .spotlight($0)})) {
            Text("Content created").tag("kMDItemContentCreationDate");Text("Content modified").tag("kMDItemContentModificationDate");Text("Added").tag("kMDItemDateAdded");Text("Downloaded").tag("kMDItemDownloadedDate")
        }
        case .referenceFile(let field):
            FolderChoice(title:"Reference folder",url:$model.options.referenceRoot)
            Picker("Reference date",selection:Binding(get:{field},set:{model.request.dates?.source = .referenceFile($0)})) {Text("Creation").tag(ReferenceDateField.creation);Text("Modification").tag(ReferenceDateField.modification);Text("Capture").tag(ReferenceDateField.capture)}
            Toggle("Allow unique basename fallback",isOn:$model.options.allowReferenceBasenameFallback)
        default:EmptyView()
        }
    }
    private func target(_ title:String,_ value:DateTargets)->some View {
        Toggle(title,isOn:Binding(get:{policy.targets.contains(value)},set:{on in var updated=policy.targets;if on {updated.insert(value)} else {updated.remove(value)};model.request.dates?.targets=updated}))
    }
}
