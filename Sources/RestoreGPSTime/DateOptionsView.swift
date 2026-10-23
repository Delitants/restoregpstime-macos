import SwiftUI
import RestoreGPSTimeCore

struct DateOptionsView:View {
    @ObservedObject var model:AppModel
    private var enabled:Binding<Bool> {Binding(get:{model.request.dates != nil},set:{var dates=DatePolicy();dates.automaticTimeZone=true;model.request.dates=$0 ? dates:nil})}
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
                    switch value {case "File creation":date.source = .fileCreation;case "File modification":date.source = .fileModification;case "Specific date":date.source = .specific(Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970)));case "Current time":date.source = .current;case "Filename pattern":date.source = .filename("yyyyMMdd_HHmmss");case "Reference file":date.source = .referenceFile(.creation);case "Spotlight field":date.source = .spotlight("kMDItemContentCreationDate");case "Qualified metadata tag":date.source = .tag("ExifIFD:DateTimeOriginal");case "Reset to 1904":date.source = .reset;default:date.source = .automaticCapture}
                    model.request.dates=date
                })) {ForEach(sources,id:\.self) {Text($0)}}
                sourceDetails
                HStack {target("Creation",.creation);target("Modification",.modification);target("Capture tags",.capture)}
                Toggle("Handle missing UTC offsets automatically",isOn:Binding(get:{policy.automaticTimeZone==true},set:{model.request.dates?.automaticTimeZone=$0}))
                if policy.automaticTimeZone==true {
                    Text("Use each photo’s embedded offset, then its GPS-based city time zone, then the fallback below. GPS zones are estimates; daylight saving uses the capture date.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("Fallback time zone for this batch").font(.caption)
                    TextField("Select once, e.g. Europe/Paris",text:Binding(get:{policy.timeZoneID ?? ""},set:{model.request.dates?.timeZoneID=$0.isEmpty ? nil:$0}))
                }
                DisclosureGroup("Time zone and video settings") {
                    VStack(alignment:.leading,spacing:10) {
                        if policy.automaticTimeZone != true {
                        TextField("Camera / output zone (e.g. Europe/Paris)",text:Binding(get:{policy.timeZoneID ?? ""},set:{model.request.dates?.timeZoneID=$0.isEmpty ? nil:$0}))
                            .help("Required for offset-free capture dates. Also selects the embedded output zone for absolute date sources.")
                        }
                        Picker("QuickTime integer dates",selection:$model.request.dates.field(\.quickTime,default:nil)) {
                            Text("Require a choice").tag(Optional<QuickTimeInterpretation>.none)
                            Text("Interpret as UTC").tag(Optional(QuickTimeInterpretation.utc))
                            Text("Camera local time in selected zone").tag(Optional(QuickTimeInterpretation.cameraLocal))
                        }
                        Picker("Repeated local hour (DST)",selection:$model.request.dates.field(\.dstChoice,default:nil)) {
                            Text("Require a choice").tag(Optional<DSTChoice>.none);Text("Earlier occurrence").tag(Optional(DSTChoice.earlier));Text("Later occurrence").tag(Optional(DSTChoice.later))
                        }
                    }.padding(.top,8)
                }
                DisclosureGroup("Shift, sequence, and removal") {
                    VStack(alignment:.leading,spacing:10) {
                        TextField("Shift (seconds)",value:$model.request.dates.field(\.shiftSeconds,default:0),format:.number.precision(.fractionLength(0...9)))
                        Toggle("Shift each original file date independently",isOn:$model.request.dates.field(\.shiftOriginalTargets,default:false))
                        Toggle("Assign a sequence",isOn:Binding(get:{policy.sequenceStart != nil},set:{model.request.dates?.sequenceStart=$0 ? Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970)):nil}))
                        if let start=policy.sequenceStart {
                            DateTimePicker(title:"Sequence start",selection:Binding(get:{start},set:{model.request.dates?.sequenceStart=$0}))
                            TextField("Step (seconds)",value:$model.request.dates.field(\.sequenceStepSeconds,default:0),format:.number.precision(.fractionLength(0...9)))
                        }
                        Toggle("Remove selected embedded capture date tags",isOn:$model.request.dates.field(\.removeEmbeddedDates,default:false)).disabled(!policy.targets.contains(.capture)).help("Select Capture tags above to remove their embedded date fields.")
                        Toggle("Require creation no later than modification",isOn:$model.request.dates.field(\.requiresMonotonicFileDates,default:false))
                        if policy.requiresMonotonicFileDates {Toggle("Allow adjusting the unselected companion date",isOn:$model.request.dates.field(\.normalizeCompanionDate,default:false))}
                    }.padding(.top,8)
                }
                Text("Embedded offsets take priority. Missing dates, nonexistent local times, and unresolved ambiguities block the affected group.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var sourceDetails:some View {
        switch policy.source {
        case .specific(let value):DateTimePicker(title:"Specific date and time",selection:Binding(get:{value},set:{model.request.dates?.source = .specific($0)}))
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
