import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class DropletTests:XCTestCase {
    private var root:URL!
    override func setUpWithError() throws {root=FileManager.default.temporaryDirectory.appendingPathComponent("RestoreGPSTimeDropletTests-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
    override func tearDownWithError() throws {if (testRun?.totalFailureCount ?? 0)>0 {print("Retained failed droplet workspace: \(root.path)");return};try FileManager.default.removeItem(at:root)}
    func testDropletRelocationAndSafeHandoff() async throws {
        let template=root.appendingPathComponent("Template.app"),resources=template.appendingPathComponent("Contents/Resources"),executable=template.appendingPathComponent("Contents/MacOS/RestoreGPSTimeDroplet")
        try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:executable.deletingLastPathComponent(),withIntermediateDirectories:true)
        // A native inert executable stands in for the UI template only for export/signing tests.
        // This is not native droplet/Finder acceptance.
        try FileManager.default.copyItem(at:URL(fileURLWithPath:"/usr/bin/true"),to:executable)
        let repo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.copyItem(at:repo.appendingPathComponent("Sources/RestoreGPSTimeCore/Resources/writable-tags.json"),to:resources.appendingPathComponent("writable-tags.json"))
        let workflow=WorkflowDocument(name:"Portable dates",request:OperationRequest()),output=root.appendingPathComponent("Portable.app")
        let result=try await DropletExporter().export(workflow:workflow,to:output,template:template)
        XCTAssertEqual(result.signature,.adHocLocal);XCTAssertNotEqual(result.bundleIdentifier,"io.github.delitants.RestoreGPSTime")
        let moved=root.appendingPathComponent("Moved.app");try FileManager.default.moveItem(at:output,to:moved)
        XCTAssertEqual(try WorkflowStore().load(from:moved.appendingPathComponent("Contents/Resources/Workflow.rgtimeworkflow")),workflow)
        let second=try await DropletExporter().export(workflow:workflow,to:root.appendingPathComponent("Second.app"),template:template)
        XCTAssertNotEqual(result.bundleIdentifier,second.bundleIdentifier)
        let urls=[root.appendingPathComponent("Photo with spaces.heic")],file=try DropletHandoff(workflow:workflow,urls:urls).write(to:root)
        XCTAssertEqual(try DropletHandoff.load(from:file).urls,urls)
        XCTAssertEqual(try FileIdentityReader().snapshot(at:file).permissions & 0o077,0)
        let conflict=root.appendingPathComponent("Already.app");try FileManager.default.createDirectory(at:conflict,withIntermediateDirectories:true)
        do {_=try await DropletExporter().export(workflow:workflow,to:conflict,template:template);XCTFail("Existing outputs must be refused")} catch {}
    }
    func testHandoffRejectsNetworkPathsUnsafeFilesAndUnknownFields() throws {
        let workflow=WorkflowDocument(name:"Test",request:OperationRequest())
        XCTAssertThrowsError(try DropletHandoff(workflow:workflow,urls:[URL(string:"https://example.invalid/photo.jpg")!]).write(to:root))
        let file=try DropletHandoff(workflow:workflow,urls:[root.appendingPathComponent("photo.jpg")]).write(to:root)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any]);object["apply"]=true
        try JSONSerialization.data(withJSONObject:object).write(to:file);XCTAssertThrowsError(try DropletHandoff.load(from:file))
        XCTAssertEqual(chmod(file.path,0o644),0);XCTAssertThrowsError(try DropletHandoff.load(from:file))
    }
}
