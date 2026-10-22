import XCTest
import AppKit
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class ImportTests:AppTestCase {
    @MainActor func testOverlappingOpenRequestsAreQueuedWithoutSilentApply() async throws {
        let input=try item(),other=try item("second.jpg"),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend),session=AppSession(model:model)
        model.options.outputRoot=workspace.appendingPathComponent("Output");await backend.delayInspection()
        let first=Task {await session.openURLs([input.snapshot.url])}
        for _ in 0..<100 {if await backend.inspectionStarted {break};try await Task.sleep(nanoseconds:1_000_000)}
        let second=Task {await session.openURLs([other.snapshot.url])};await Task.yield()
        await backend.releaseInspection()
        let firstResult=await first.value,secondResult=await second.value
        XCTAssertTrue(firstResult.errors.isEmpty);XCTAssertTrue(secondResult.errors.isEmpty)
        let inspected=await backend.inspectionInputs,executions=await backend.executions
        XCTAssertEqual(inspected.count,2);XCTAssertTrue(inspected.last?.contains(other.snapshot.url)==true);XCTAssertEqual(executions,0)
    }
    @MainActor func testAppAndServicesOpenSameImports() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend),importer=DocumentImporter(model:model)
        model.options.outputRoot=workspace.appendingPathComponent("Output")
        let result=await importer.open(urls:[input.snapshot.url])
        XCTAssertTrue(result.errors.isEmpty);XCTAssertEqual(model.rows.count,1);XCTAssertNotNil(model.plan)
        let services=ServicesProvider(importer:importer)
        let second=await services.importURLs([input.snapshot.url])
        XCTAssertTrue(second.errors.isEmpty);XCTAssertEqual(model.rows.count,1)
        let count=await backend.executions;XCTAssertEqual(count,0)
    }
    @MainActor func testDropletNeverAppliesSilently() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend),importer=DocumentImporter(model:model)
        model.options.outputRoot=workspace.appendingPathComponent("Old output");model.options.recoveryRoot=workspace.appendingPathComponent("Old recovery");model.options.mode = .modifyInPlace
        var request=OperationRequest();request.dates=DatePolicy();request.rename=NameTemplate("{original} - {sequence:04}.{extension}")
        let file=try DropletHandoff(workflow:.init(name:"Portable",request:request),urls:[input.snapshot.url]).write(to:workspace)
        let result=await importer.open(urls:[file])
        XCTAssertTrue(result.errors.isEmpty);XCTAssertEqual(model.rows.count,1);XCTAssertEqual(model.request.rename,request.rename)
        XCTAssertNil(model.options.outputRoot);XCTAssertNil(model.options.recoveryRoot);XCTAssertEqual(model.options.mode,.saveCopies)
        XCTAssertNil(model.plan);XCTAssertEqual(model.issue,"Choose the Save Copies folder.");XCTAssertFalse(model.canApply)
        let count=await backend.executions;XCTAssertEqual(count,0)
    }
    @MainActor func testInvalidWorkflowCannotChangeExistingBatchOrImportFiles() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend),importer=DocumentImporter(model:model)
        await model.importURLs([input.snapshot.url]);let before=model.request
        let invalid=workspace.appendingPathComponent("Invalid.rgtimeworkflow");try Data("{\"schema\":99}".utf8).write(to:invalid)
        let result=await importer.open(urls:[invalid,input.snapshot.url])
        XCTAssertFalse(result.errors.isEmpty);XCTAssertEqual(model.request,before);XCTAssertEqual(model.rows.count,1)
    }
}
