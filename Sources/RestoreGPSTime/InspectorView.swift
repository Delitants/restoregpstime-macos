import SwiftUI
import RestoreGPSTimeCore
struct InspectorView:View {
    @ObservedObject var model:AppModel
    let row:MediaRow?
    @State private var city=""
    @State private var country=""
    @State private var region=""
    @State private var countryCode=""
    @State private var metadataSearch=""
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text("File inspector").font(.headline)
                if let row {
                    Text(row.fileName).font(.title3).textSelection(.enabled)
                    Text(row.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let issue=row.issue {Text(issue).foregroundStyle(.orange).textSelection(.enabled)}
                    if let item=row.item {
                        Text("Format: \(item.metadata.profile.identifier)").font(.caption)
                        detail("Current creation",displayDate(item.snapshot.creationDate));detail("Current modification",displayDate(item.snapshot.modificationDate))
                        if let plan=row.planned {
                            Divider();Text("Frozen preview").font(.headline)
                            detail("Output",plan.name.finalURL.path)
                            detail("Proposed creation",displayDate(plan.mutation.dates?.creationDate));detail("Proposed modification",displayDate(plan.mutation.dates?.modificationDate))
                            if let resolution=plan.resolution {detail("Date source",resolution.source);detail("Original date",resolution.original);detail("Interpretation",resolution.interpretation);ForEach(resolution.warnings,id:\.self) {Text($0).font(.caption).foregroundStyle(.orange)}}
                            if let group=model.plan?.groups.first(where:{$0.id==row.groupID}) {detail("Asset grouping",group.evidence)}
                            if let place=plan.place {detail(place.origin == .manual ? "Manual correction":"Nearby place (approximate)",place.displayName);if let distance=place.distanceKM {Text(String(format:"%.2f km from stored coordinates",distance)).font(.caption)};detail("Database",place.databaseIdentity)}
                            if let tags=try? MetadataMutationDriver.expandedTags(plan.mutation,document:plan.metadata),!tags.isEmpty {
                                DisclosureGroup("Actual metadata destinations (\(tags.count))") {
                                    ForEach(Array(tags.enumerated()),id:\.offset) {_,tag in
                                        switch tag {case .set(let id,let value):detail(id.rawValue,value.text);case .remove(let id):detail(id.rawValue,"Remove")}
                                    }
                                }
                            }
                            ForEach(plan.capabilities.keys.sorted(),id:\.self) {key in if let decision=plan.capabilities[key] {detail(key,String(describing:decision))}}
                        }
                        Divider()
                        DisclosureGroup("Correct place name") {
                            VStack(alignment:.leading,spacing:6) {
                                TextField("City",text:$city);TextField("Region",text:$region);TextField("Country",text:$country);TextField("Country code",text:$countryCode)
                                HStack {
                                    Button("Use Correction") {model.request.placeOverrides[item.snapshot.id.physicalKey] = .init(city:city,region:region,country:country,countryCode:countryCode)}.disabled(city.isEmpty && country.isEmpty)
                                    Button("Clear") {model.request.placeOverrides.removeValue(forKey:item.snapshot.id.physicalKey);loadCorrection()}
                                }
                            }.padding(.top,8)
                        }
                        Toggle("Exclude from this batch",isOn:Binding(get:{model.request.excludedSourceKeys.contains(item.snapshot.id.physicalKey)},set:{if $0 {model.request.excludedSourceKeys.insert(item.snapshot.id.physicalKey)} else {model.request.excludedSourceKeys.remove(item.snapshot.id.physicalKey)}}))
                        Toggle("Unlink this asset explicitly",isOn:Binding(get:{model.request.groups.unlinkedSourceKeys.contains(item.snapshot.id.physicalKey)},set:{if $0 {model.request.groups.unlinkedSourceKeys.insert(item.snapshot.id.physicalKey)} else {model.request.groups.unlinkedSourceKeys.remove(item.snapshot.id.physicalKey)}}))
                        if !item.metadata.ambiguousIdentifiers.isEmpty {Text("Conflicting metadata copies: "+item.metadata.ambiguousIdentifiers.sorted().joined(separator:", ")).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                        if !item.metadata.occurrences.isEmpty {
                            DisclosureGroup("Metadata copy provenance") {
                                ForEach(Array(item.metadata.occurrences.enumerated()),id:\.offset) {_,field in detail(field.selectableID,field.value.text)}
                            }
                        }
                        ForEach(item.metadata.diagnostics,id:\.self) {Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                        Divider()
                        DisclosureGroup("Read metadata (\(item.metadata.tags.count) fields)") {
                            TextField("Filter qualified tags",text:$metadataSearch)
                            ForEach(item.metadata.tags.keys.sorted().filter {metadataSearch.isEmpty || $0.localizedCaseInsensitiveContains(metadataSearch)},id:\.self) {key in detail(key,item.metadata.tags[key]?.text ?? "")}
                        }
                    }
                } else {Text("Select a row to review its source metadata, date interpretation, place estimate, and proposed changes.").foregroundStyle(.secondary)}
            }.padding(16)
        }.frame(minWidth:250,idealWidth:285,maxWidth:380)
        .onAppear(perform:loadCorrection).onChange(of:row?.id) {_ in loadCorrection()}
        .accessibilityLabel("Selected file details")
    }
    private func detail(_ title:String,_ value:String)->some View {VStack(alignment:.leading,spacing:3) {Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.caption).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)}}
    private func loadCorrection() {let place=row?.item.flatMap {model.request.placeOverrides[$0.snapshot.id.physicalKey]} ?? row?.planned?.place;city=place?.city ?? "";country=place?.country ?? "";region=place?.region ?? "";countryCode=place?.countryCode ?? ""}
}
