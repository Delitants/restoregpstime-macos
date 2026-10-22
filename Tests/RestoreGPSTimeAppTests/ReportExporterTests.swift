import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class ReportExporterTests:AppTestCase {
    private func report() async throws -> BatchReport {
        let input=try item("=SUM(1,1).jpg"),backend=FakeAppBackend(items:[input])
        var options=BatchOptions();options.outputRoot=workspace.appendingPathComponent("Output");options.recoveryRoot=workspace.appendingPathComponent("Recovery")
        var request=OperationRequest();request.tags=[.set(TagID(rawValue:"XMP-dc:Subject")!,.array([.string("one"),.string("two")]))]
        let plan=try await backend.preview(items:[input],request:request,options:options)
        return .init(plan:plan,startedAt:Date(),results:plan.groups.map {.init(groupID:$0.id,status:.failed,errors:["Unchanged synthetic input"])},cancelled:false)
    }
    func testReportPreservesExactPlannedDatesAndActualTagDestinations() async throws {
        let base=try item(),document=MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05"),"ExifIFD:SubSecTimeOriginal":.string("123456789"),"ExifIFD:OffsetTimeOriginal":.string("+02:00")],profile:.init(identifier:"JPEG",family:.photo))
        let input=InspectedItem(snapshot:base.snapshot,metadata:document),backend=FakeAppBackend(items:[input])
        var request=OperationRequest();var policy=DatePolicy();policy.targets=[.creation,.modification,.capture];policy.shiftSeconds=3600;request.dates=policy
        var options=BatchOptions();options.outputRoot=workspace.appendingPathComponent("Output")
        let plan=try await backend.preview(items:[input],request:request,options:options),report=BatchReport(plan:plan,startedAt:Date(),results:[],cancelled:false),file=workspace.appendingPathComponent("precise.json")
        try ReportExporter().export(report,to:file)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any]),entries=try XCTUnwrap(object["entries"] as? [[String:Any]]),row=try XCTUnwrap(entries.first)
        XCTAssertEqual(row["plannedCreation"] as? String,"2024-01-02T02:04:05.123456789Z")
        XCTAssertEqual(row["plannedCapture"] as? String,"2024-01-02T02:04:05.123456789Z")
        let changes=try XCTUnwrap(row["metadataChanges"] as? [String:[String:Any]])
        XCTAssertEqual(changes["ExifIFD:SubSecTimeOriginal"]?["value"] as? String,"123456789")
    }
    func testReportCoordinatesDefaultOffAndJSONKeepsTypes() async throws {
        let report=try await report(),file=workspace.appendingPathComponent("report.json")
        try ReportExporter().export(report,to:file)
        let data=try Data(contentsOf:file),text=String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("48.8566"));XCTAssertFalse(text.contains("GPSLatitude"))
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]),entries=try XCTUnwrap(object["entries"] as? [[String:Any]])
        let changes=try XCTUnwrap(entries.first?["metadataChanges"] as? [String:[String:Any]])
        XCTAssertEqual(object["recoveryRoot"] as? String,report.plan.options.recoveryRoot?.path)
        XCTAssertEqual(changes["XMP-dc:Subject"]?["value"] as? [String],["one","two"])
        let optIn=workspace.appendingPathComponent("coordinates.json");try ReportExporter().export(report,to:optIn,includeCoordinates:true)
        XCTAssertTrue(try String(contentsOf:optIn).contains("48.8566"))
    }
    func testCSVFormulaStringsAreData() async throws {
        let report=try await report(),file=workspace.appendingPathComponent("report.csv")
        try ReportExporter().export(report,to:file)
        let text=try String(contentsOf:file)
        XCTAssertTrue(text.contains("'=SUM(1,1).jpg"));XCTAssertFalse(text.contains("48.8566"))
    }
}
