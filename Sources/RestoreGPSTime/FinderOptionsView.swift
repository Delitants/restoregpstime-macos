import SwiftUI
import RestoreGPSTimeCore
struct FinderOptionsView:View {
    @ObservedObject var model:AppModel
    @State private var type=""
    @State private var creator=""
    @State private var validation:String?
    private func replace(_ test:(FinderMutation)->Bool,_ value:FinderMutation?) {model.request.finder.removeAll(where:test);if let value {model.request.finder.append(value)}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Finder attributes").font(.headline)
            Picker("Filename extension",selection:Binding(get:{model.request.finder.compactMap {if case .extensionHidden(let v)=$0 {return v ? 1:0};return nil}.first ?? -1},set:{n in replace({if case .extensionHidden=$0 {return true};return false},n<0 ? nil:.extensionHidden(n==1))})) {Text("Preserve").tag(-1);Text("Show").tag(0);Text("Hide").tag(1)}
            Picker("Locked flag",selection:Binding(get:{model.request.finder.compactMap {if case .locked(let v)=$0 {return v ? 1:0};return nil}.first ?? -1},set:{n in replace({if case .locked=$0 {return true};return false},n<0 ? nil:.locked(n==1))})) {Text("Preserve").tag(-1);Text("Unlock explicitly").tag(0);Text("Lock after processing").tag(1)}
            Picker("Legacy Finder label",selection:Binding(get:{model.request.finder.compactMap {if case .label(let v)=$0 {return v};return nil}.first ?? -1},set:{n in replace({if case .label=$0 {return true};return false},n<0 ? nil:.label(n))})) {Text("Preserve").tag(-1);ForEach(0..<8) {Text($0==0 ? "None":"Label \($0)").tag($0)}}
            Toggle("Remove Where Froms metadata",isOn:Binding(get:{model.request.finder.contains(.removeWhereFroms)},set:{replace({$0 == .removeWhereFroms},$0 ? .removeWhereFroms:nil)}))
            Toggle("Notify Finder after processing",isOn:Binding(get:{model.request.finder.contains(.notify)},set:{replace({$0 == .notify},$0 ? .notify:nil)}))
            DisclosureGroup("Legacy type and creator codes") {
                VStack(alignment:.leading) {
                    TextField("File type (4 bytes)",text:$type);TextField("Creator (4 bytes)",text:$creator)
                    Button("Set Codes") {
                        guard [type,creator].allSatisfy({$0.isEmpty || $0.data(using:.macOSRoman)?.count==4}) else {validation="Each selected code must encode as exactly four MacRoman bytes.";return}
                        replace({if case .fileType=$0 {return true};return false},type.isEmpty ? nil:.fileType(type.data(using:.macOSRoman)!))
                        replace({if case .creator=$0 {return true};return false},creator.isEmpty ? nil:.creator(creator.data(using:.macOSRoman)!));validation=nil
                    }
                    if let validation {Text(validation).foregroundStyle(.orange)}
                }.padding(.top,8)
            }
            Text("Global Show / Hide Hidden Files commands are in Tools. They require their own review and never run as a batch side effect.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
