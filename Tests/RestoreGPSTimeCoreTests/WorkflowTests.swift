import XCTest
@testable import RestoreGPSTimeCore

final class WorkflowTests:XCTestCase {
    func testWorkflowRoundTrip() throws {
        var request=OperationRequest();var dates=DatePolicy();dates.timeZoneID="Europe/Paris";dates.quickTime = .cameraLocal;request.dates=dates;request.rename=NameTemplate()
        let document=WorkflowDocument(name:"Restore camera dates",request:request),store=WorkflowStore()
        let data=try store.encode(document),loaded=try store.decode(data)
        XCTAssertEqual(loaded,document);XCTAssertEqual(loaded.request.dates?.timeZoneID,"Europe/Paris")
    }
    func testUnknownSchemaAndExecutableFieldsRejected() throws {
        let store=WorkflowStore(),data=try store.encode(.init(name:"Test",request:OperationRequest()))
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        object["schema"]=2;XCTAssertThrowsError(try store.decode(JSONSerialization.data(withJSONObject:object)))
        object["schema"]=1;object["shell"]="do not run";XCTAssertThrowsError(try store.decode(JSONSerialization.data(withJSONObject:object)))
        object.removeValue(forKey:"shell");var request=try XCTUnwrap(object["request"] as? [String:Any]);request["script"]=true;object["request"]=request
        XCTAssertThrowsError(try store.decode(JSONSerialization.data(withJSONObject:object)))
    }
    func testWorkflowOmitsSourceOutputAndRecoveryPaths() throws {
        var request=OperationRequest();request.placeOverrides["private-file-key"] = .init(city:"Private city",country:"Private country");request.excludedSourceKeys=["private-file-key"];request.groups.forcedGroups=[["private-file-key","another-private-key"]]
        let document=WorkflowDocument(name:"Portable",request:request),data=try WorkflowStore().encode(document),text=String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("private-file-key"));XCTAssertFalse(text.contains("Private city"));XCTAssertFalse(text.contains("another-private-key"))
        XCTAssertFalse(text.contains("outputRoot"));XCTAssertFalse(text.contains("recoveryRoot"));XCTAssertFalse(text.contains("importRoots"))
        XCTAssertTrue(document.request.placeOverrides.isEmpty);XCTAssertTrue(document.request.excludedSourceKeys.isEmpty);XCTAssertTrue(document.request.groups.forcedGroups.isEmpty)
    }
    func testNestedUnknownFieldsAndPathTemplatesRejected() throws {
        let store=WorkflowStore();var request=OperationRequest();request.dates=DatePolicy()
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:store.encode(.init(name:"Test",request:request))) as? [String:Any])
        var settings=try XCTUnwrap(object["request"] as? [String:Any]),dates=try XCTUnwrap(settings["dates"] as? [String:Any]);dates["executable"]="/bin/sh";settings["dates"]=dates;object["request"]=settings
        XCTAssertThrowsError(try store.decode(JSONSerialization.data(withJSONObject:object)))
        request.rename=NameTemplate("../{original}.{extension}")
        XCTAssertThrowsError(try store.encode(.init(name:"Bad path",request:request)))
    }
}
