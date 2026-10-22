import SwiftUI
import AppKit

struct DateTimePicker:View {
    let title:String
    @Binding var selection:Date
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            CalendarFields(title:title,selection:$selection).frame(height:26)
            Text("Calendar input: \(TimeZone.current.identifier), whole seconds.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
private struct CalendarFields:NSViewRepresentable {
    let title:String
    @Binding var selection:Date
    func makeNSView(context:Context)->NSDatePicker {
        let picker=NSDatePicker();picker.datePickerStyle = .textFieldAndStepper;picker.datePickerMode = .single;picker.datePickerElements=[.yearMonthDay,.hourMinuteSecond]
        picker.timeZone = .current;picker.locale = .current;picker.dateValue=selection
        picker.target=context.coordinator;picker.action=#selector(Coordinator.changed(_:));picker.setAccessibilityLabel(title)
        return picker
    }
    func updateNSView(_ picker:NSDatePicker,context:Context) {context.coordinator.selection=$selection;if picker.dateValue != selection {picker.dateValue=selection}}
    func makeCoordinator()->Coordinator {Coordinator(selection:$selection)}
    final class Coordinator:NSObject {
        var selection:Binding<Date>
        init(selection:Binding<Date>) {self.selection=selection}
        @objc func changed(_ sender:NSDatePicker) {selection.wrappedValue=Date(timeIntervalSince1970:floor(sender.dateValue.timeIntervalSince1970))}
    }
}
