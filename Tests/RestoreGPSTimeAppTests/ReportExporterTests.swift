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
