import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

actor FakeAppBackend:AppBackend {
    let items:[InspectedItem]
    var excluded=[ExcludedSource]()
    private(set) var executions=0,restorations=0
    private(set) var inspectionInputs=[[URL]]()
    var failure=false,hold=false
    private(set) var inspectionStarted=false,previewStarted=false
    var holdInspection=false,holdPreview=false
    private var inspectionGate:CheckedContinuation<Void,Never>?,previewGate:CheckedContinuation<Void,Never>?
    private var activePlan:BatchPlan?,continuation:AsyncStream<BatchEvent>.Continuation?
    init(items:[InspectedItem]) {self.items=items}
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem] {
        inspectionStarted=true;inspectionInputs.append(urls)
        if holdInspection {await withCheckedContinuation {inspectionGate=$0}}
        return items
    }
    func setExcluded(_ value:[ExcludedSource]) {excluded=value}
    func inspectDetailed(_ urls:[URL],options:DiscoveryOptions) async throws -> AppInspection {.init(items:try await inspect(urls,options:options),excluded:excluded)}
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {
        let result=try await BatchPlanner(dependencies:.init(engineHash:"test-engine",databaseHash:"test-db",capabilityHash:"test-policy")).preview(items:items,request:request,options:options)
        previewStarted=true
        if holdPreview {await withCheckedContinuation {previewGate=$0}}
        return result
    }
    func delayInspection() {holdInspection=true;inspectionStarted=false}
    func releaseInspection() {holdInspection=false;inspectionGate?.resume();inspectionGate=nil}
    func delayPreview() {holdPreview=true;previewStarted=false}
    func releasePreview() {holdPreview=false;previewGate?.resume();previewGate=nil}
    func setFailure(_ value:Bool) {failure=value}
    func setHold(_ value:Bool) {hold=value}
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent> {
        executions+=1;activePlan=plan
        return AsyncStream {stream in
            continuation=stream;stream.yield(.started(plan.id,totalGroups:plan.groups.count))
            if !hold {stream.yield(.finished(result(plan,cancelled:false)));stream.finish()}
        }
    }
    func cancel(_ id:UUID) async {
        guard let plan=activePlan,plan.id==id else {return}
        continuation?.yield(.finished(result(plan,cancelled:true)));continuation?.finish()
    }
    private func result(_ plan:BatchPlan,cancelled:Bool)->BatchReport {
        .init(plan:plan,startedAt:Date(),results:plan.groups.map {group in
            .init(groupID:group.id,status:group.eligibility == .blocked ? .blocked:(cancelled ? .cancelled:(failure ? .failed:.committed)),outputs:failure || cancelled ? []:group.items.map { $0.name.finalURL },errors:failure ? ["Injected executor failure"]:group.blockingReasons)
        },cancelled:cancelled)
    }
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {
        restorations+=1;return .init(batchID:batchID,restored:[],conflicts:[])
    }
}
class AppTestCase:XCTestCase {
    var workspace:URL!
    override func setUpWithError() throws {workspace=FileManager.default.temporaryDirectory.appendingPathComponent("RestoreGPSTimeAppTests-"+UUID().uuidString);try FileManager.default.createDirectory(at:workspace,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {if (testRun?.totalFailureCount ?? 0)>0 {print("Retained failed AppTests workspace: \(workspace.path)");return};try FileManager.default.removeItem(at:workspace)}
    func item(_ name:String="photo.jpg",validDate:Bool=true) throws -> InspectedItem {
        let url=workspace.appendingPathComponent(name);try Data("synthetic model fixture".utf8).write(to:url)
        let tags:[String:TagValue]=validDate ? ["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05Z"),"GPS:GPSLatitude":.real(48.8566),"GPS:GPSLongitude":.real(2.3522)]:[:]
        return .init(snapshot:try FileIdentityReader().snapshot(at:url),metadata:.init(tags:tags,profile:.init(identifier:"JPEG",family:.photo)),place:.init(city:"Paris",country:"France"))
    }
}
final class AppModelTests:AppTestCase {
    @MainActor func testFailedPreviewStopsBusyGuidanceAndNewSettingsClearItsIssue() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        await model.importURLs([input.snapshot.url]);await model.preview()
        XCTAssertEqual(model.phase,.failed);XCTAssertNotNil(model.issue)
        XCTAssertFalse(model.progress.contains("Building"));XCTAssertFalse(model.isBusy)
        model.options.outputRoot=workspace.appendingPathComponent("Selected copies")
        XCTAssertNil(model.issue);XCTAssertEqual(model.phase,.idle);XCTAssertFalse(model.canApply)
    }
    @MainActor func testExcludedImportsRemainVisibleAfterPreview() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend),excluded=workspace.appendingPathComponent("Unavailable.app")
        await backend.setExcluded([.init(url:excluded,reason:"Packages are excluded")]);model.options.outputRoot=workspace.appendingPathComponent("Output")
        await model.importURLs([input.snapshot.url,excluded]);XCTAssertEqual(model.rows.count,2)
        await model.preview();XCTAssertEqual(model.rows.count,2);XCTAssertTrue(model.rows.contains {$0.status=="excluded" && $0.issue=="Packages are excluded"})
    }
    @MainActor func testOptionChangeDuringImportDiscardsStaleRowsWithoutStuckBusyState() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        await backend.delayInspection()
        let work=Task {await model.importURLs([input.snapshot.url])}
        for _ in 0..<100 {if await backend.inspectionStarted {break};try await Task.sleep(nanoseconds:1_000_000)}
        model.options.outputRoot=workspace.appendingPathComponent("Changed output")
        await backend.releaseInspection();await work.value
        XCTAssertTrue(model.rows.isEmpty);XCTAssertEqual(model.phase,.idle);XCTAssertFalse(model.isBusy)
    }
    @MainActor func testAsyncOldPreviewCannotBecomeCurrentAfterOptionChange() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        model.options.outputRoot=workspace.appendingPathComponent("Output");await model.importURLs([input.snapshot.url]);await backend.delayPreview()
        let work=Task {await model.preview()}
        for _ in 0..<100 {if await backend.previewStarted {break};try await Task.sleep(nanoseconds:1_000_000)}
        model.request.dates?.timeZoneID="Europe/Paris"
        await backend.releasePreview();await work.value
        XCTAssertNil(model.plan);XCTAssertFalse(model.canApply);XCTAssertEqual(model.phase,.idle)
    }
    @MainActor func testInspectorUsesFrozenDateTagDestinationsAndManualPlace() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        model.options.outputRoot=workspace.appendingPathComponent("Output")
        model.request.dates?.targets.insert(.capture);model.request.location=LocationWriteOptions()
        let correction=PlaceMatch(city:"Custom city",country:"Custom country")
        model.request.placeOverrides[input.snapshot.id.physicalKey]=correction
        await model.importURLs([input.snapshot.url]);await model.preview()
        let planned=try XCTUnwrap(model.rows.first?.planned)
        XCTAssertEqual(planned.place,correction);XCTAssertEqual(planned.resolution?.source,"ExifIFD:DateTimeOriginal")
        let tags=try MetadataMutationDriver.expandedTags(planned.mutation,document:planned.metadata)
        XCTAssertTrue(tags.contains {if case .set(let key,let value)=$0 {return key.rawValue=="ExifIFD:UserComment" && value.text==correction.displayName};return false})
        XCTAssertTrue(tags.contains {if case .set(let key,_)=$0 {return key.rawValue=="ExifIFD:DateTimeOriginal"};return false})
    }
    @MainActor func testDefaultIsSaveCopies() {
        let model=AppModel(backend:FakeAppBackend(items:[]));XCTAssertEqual(model.options.mode,.saveCopies);XCTAssertFalse(model.canApply)
    }
    @MainActor func testApplyDisabledWithoutCurrentPreview() async {
        let backend=FakeAppBackend(items:[]),model=AppModel(backend:backend)
        await model.applyPreview();let count=await backend.executions;XCTAssertEqual(count,0)
    }
    @MainActor func testChangingTimezoneOrNamesInvalidatesPreview() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        model.options.outputRoot=workspace.appendingPathComponent("Output")
        await model.importURLs([input.snapshot.url]);await model.preview();XCTAssertTrue(model.canApply)
        model.request.dates?.timeZoneID="Europe/Paris";XCTAssertNil(model.plan);XCTAssertFalse(model.canApply)
        await model.applyPreview();let count=await backend.executions;XCTAssertEqual(count,0)
        await model.preview();XCTAssertTrue(model.canApply)
        model.request.rename=NameTemplate();XCTAssertNil(model.plan);XCTAssertFalse(model.canApply)
    }
    @MainActor func testBlockedAndFailedRowsRemainVisible() async throws {
        let good=try item("good.jpg"),bad=try item("missing-date.jpg",validDate:false),backend=FakeAppBackend(items:[good,bad]),model=AppModel(backend:backend)
        model.options.outputRoot=workspace.appendingPathComponent("Output");await backend.setFailure(true)
        await model.importURLs([good.snapshot.url,bad.snapshot.url]);await model.preview()
        XCTAssertEqual(model.rows.count,2);XCTAssertTrue(model.rows.contains {$0.status=="blocked"});XCTAssertTrue(model.canApply)
        await model.applyPreview();XCTAssertEqual(model.rows.count,2);XCTAssertTrue(model.rows.contains {$0.status=="failed"});XCTAssertNotNil(model.report)
    }
    @MainActor func testCancellationAndRecoveryStates() async throws {
        let input=try item(),backend=FakeAppBackend(items:[input]),model=AppModel(backend:backend)
        model.options.outputRoot=workspace.appendingPathComponent("Output");await backend.setHold(true)
        await model.importURLs([input.snapshot.url]);await model.preview()
        let work=Task {await model.applyPreview()}
        for _ in 0..<100 {if await backend.executions>0 {break};try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(model.phase,.running);model.cancel();await work.value
        XCTAssertEqual(model.phase,.finished);XCTAssertTrue(model.report?.cancelled==true)
        await model.restore(batchID:try XCTUnwrap(model.report?.batchID),choice:.originalLocations)
        let count=await backend.restorations;XCTAssertEqual(count,1);XCTAssertEqual(model.phase,.finished)
    }
}
