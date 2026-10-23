import XCTest
@testable import RestoreGPSTimeCore

final class PreviewCompositionTests:CoreTestCase {
    private let identity=DependencyIdentity(engineHash:"test",databaseHash:"db",capabilityHash:"policy")
    private func input() throws -> InspectedItem {
        let url=workspace.appendingPathComponent("original.jpg")
        try FileManager.default.copyItem(at:fixture("paris.jpg"),to:url)
        return .init(snapshot:try FileIdentityReader().snapshot(at:url),metadata:.init(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05+02:00")],profile:.init(identifier:"JPEG",family:.photo)),place:.init(city:"Madrid",country:"Spain"))
    }
    func testScopedLocationPreviewNeverIncludesDatesOrFinderChanges() {
        var all=OperationRequest();all.dates=DatePolicy();all.location=LocationWriteOptions();all.rename=NameTemplate();all.finder=[.label(3)]
        let places=PreviewComponent.places.request(from:all)
        XCTAssertNil(places.dates);XCTAssertTrue(places.finder.isEmpty);XCTAssertNotNil(places.location);XCTAssertFalse(places.rename.preserveOriginal)
        let dates=PreviewComponent.dates.request(from:all)
        XCTAssertNotNil(dates.dates);XCTAssertNil(dates.location);XCTAssertTrue(dates.rename.preserveOriginal)
    }
    func testCombinesExactDatesAndPreviouslyPreviewedNamesWithoutReplanning() async throws {
        let item=try input();var all=OperationRequest();all.dates=DatePolicy();all.rename=NameTemplate()
        var options=BatchOptions();options.mode = .modifyInPlace
        let planner=BatchPlanner(dependencies:identity)
        let dates=try await planner.preview(items:[item],request:PreviewComponent.dates.request(from:all),options:options)
        let places=try await planner.preview(items:[item],request:PreviewComponent.places.request(from:all),options:options)
        let combined=try await BatchPlanComposer().combine(components:[.dates:dates,.places:places],request:all,options:options)
        let output=try XCTUnwrap(combined.groups.first?.items.first)
        XCTAssertEqual(output.mutation.dates?.creationDate,try utc("2024-01-02T01:04:05Z"))
        XCTAssertEqual(output.name.finalURL.lastPathComponent,"Spain - Madrid - 0001.jpg")
        XCTAssertEqual(combined.eligibleGroups.count,1)
    }
    func testPreviewWithoutCopyDestinationHasProposalsButCannotExecute() async throws {
        let item=try input();var request=OperationRequest();request.dates=DatePolicy()
        let plan=try await BatchPlanner(dependencies:identity).preview(items:[item],request:request,options:BatchOptions(),allowUnresolvedDestination:true)
        XCTAssertTrue(plan.destinationPending)
        XCTAssertEqual(plan.eligibleGroups.count,1)
        XCTAssertNotNil(plan.groups.first?.items.first?.mutation.dates?.creationDate)
        let validation=await PlanValidator(dependencies:{self.identity}).revalidate(plan)
        XCTAssertFalse(validation.isValid)
        let folder=workspace.appendingPathComponent("Copies");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let bound=try await BatchPlanComposer().bindDestination(plan,to:folder)
        XCTAssertFalse(bound.destinationPending)
        XCTAssertTrue(bound.groups.first?.items.first?.name.finalURL.path.hasPrefix(folder.path+"/")==true)
        XCTAssertEqual(bound.groups.first?.items.first?.name.finalURL.lastPathComponent,"original.jpg")
        let boundValidation=await PlanValidator(dependencies:{self.identity}).revalidate(bound)
        XCTAssertTrue(boundValidation.isValid)
    }
    func testDestinationCollisionDoesNotSilentlyChangeThePreviewedName() async throws {
        let item=try input();var request=OperationRequest();request.rename=NameTemplate()
        let plan=try await BatchPlanner(dependencies:identity).preview(items:[item],request:request,options:BatchOptions(),allowUnresolvedDestination:true)
        let folder=workspace.appendingPathComponent("Copies");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try Data("existing user file".utf8).write(to:folder.appendingPathComponent("Spain - Madrid - 0001.jpg"))
        let bound=try await BatchPlanComposer().bindDestination(plan,to:folder)
        XCTAssertEqual(bound.eligibleGroups.count,0)
        XCTAssertEqual(bound.groups.first?.items.first?.name.finalURL.lastPathComponent,"Spain - Madrid - 0001.jpg")
        XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent("Spain - Madrid - 0001.jpg")),"existing user file")
    }
    func testChangingCopyDestinationRebindsCachedNamesToNewFolder() async throws {
        let item=try input();var request=OperationRequest();request.rename=NameTemplate()
        var options=BatchOptions();options.outputRoot=workspace.appendingPathComponent("Old")
        try FileManager.default.createDirectory(at:options.outputRoot!,withIntermediateDirectories:true)
        let cached=try await BatchPlanner(dependencies:identity).preview(items:[item],request:PreviewComponent.places.request(from:request),options:options)
        options.outputRoot=workspace.appendingPathComponent("New")
        try FileManager.default.createDirectory(at:options.outputRoot!,withIntermediateDirectories:true)
        let combined=try await BatchPlanComposer().combine(components:[.places:cached],request:request,options:options)
        XCTAssertEqual(combined.groups.first?.items.first?.name.finalURL.deletingLastPathComponent().path,options.outputRoot?.path)
        XCTAssertEqual(combined.groups.first?.items.first?.name.finalURL.lastPathComponent,cached.groups.first?.items.first?.name.finalURL.lastPathComponent)
    }
    func testSidecarUsesCombinedRenamedMediaStem() async throws {
        let item=try input();var request=OperationRequest();var dates=DatePolicy();dates.targets=[.creation,.capture];request.dates=dates;request.rename=NameTemplate();request.metadataDestination = .xmpSidecar
        var options=BatchOptions();options.mode = .modifyInPlace
        let planner=BatchPlanner(dependencies:identity)
        let datePlan=try await planner.preview(items:[item],request:PreviewComponent.dates.request(from:request),options:options)
        let placePlan=try await planner.preview(items:[item],request:PreviewComponent.places.request(from:request),options:options)
        let combined=try await BatchPlanComposer().combine(components:[.dates:datePlan,.places:placePlan],request:request,options:options)
        let sidecar=try XCTUnwrap(combined.groups.flatMap(\.items).first {$0.mutation.outputKind == .xmpSidecar})
        XCTAssertEqual(sidecar.name.finalURL.lastPathComponent,"Spain - Madrid - 0001.xmp")
        XCTAssertEqual(combined.eligibleGroups.count,1)
    }
    func testChangedSourceBetweenTabPreviewsIsRejected() async throws {
        let item=try input();var request=OperationRequest();request.dates=DatePolicy();request.rename=NameTemplate()
        var options=BatchOptions();options.mode = .modifyInPlace
        let planner=BatchPlanner(dependencies:identity)
        let datePlan=try await planner.preview(items:[item],request:PreviewComponent.dates.request(from:request),options:options)
        let handle=try FileHandle(forWritingTo:item.snapshot.url);try handle.seekToEnd();try handle.write(contentsOf:Data("change".utf8));try handle.close()
        let changed=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:item.snapshot.url),metadata:item.metadata,place:item.place)
        let placePlan=try await planner.preview(items:[changed],request:PreviewComponent.places.request(from:request),options:options)
        do {_ = try await BatchPlanComposer().combine(components:[.dates:datePlan,.places:placePlan],request:request,options:options);XCTFail("Different source versions cannot be composed")} catch {}
    }

    func testChangedRecoveryRootCannotMutateSelectedDirectoryBeforeCommit() async throws {
        let directory=workspace.appendingPathComponent("Selected");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let snapshot=try FileIdentityReader().snapshot(at:directory),item=InspectedItem(snapshot:snapshot,metadata:.init(tags:[:]))
        var request=OperationRequest();var dates=DatePolicy();dates.source = .specific(try utc("2024-01-02T03:04:05Z"));request.dates=dates
        var options=BatchOptions();options.mode = .modifyInPlace
        let cached=try await BatchPlanner(dependencies:identity).preview(items:[item],request:PreviewComponent.dates.request(from:request),options:options)
        options.recoveryRoot=directory.appendingPathComponent("Recovery")
        do {_ = try await BatchPlanComposer().combine(components:[.dates:cached],request:request,options:options);XCTFail("Creating recovery storage would mutate selected directory")} catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:options.recoveryRoot!.path));XCTAssertEqual(try FileIdentityReader().snapshot(at:directory),snapshot)
    }
    func testOldCopyCollisionIsReevaluatedForNewClearDestination() async throws {
        let item=try input();var request=OperationRequest();request.dates=DatePolicy()
        let occupied=workspace.appendingPathComponent("Occupied"),clear=workspace.appendingPathComponent("Clear")
        try FileManager.default.createDirectory(at:occupied,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:clear,withIntermediateDirectories:true)
        try Data("existing".utf8).write(to:occupied.appendingPathComponent("original.jpg"))
        var options=BatchOptions();options.outputRoot=occupied
        let cached=try await BatchPlanner(dependencies:identity).preview(items:[item],request:PreviewComponent.dates.request(from:request),options:options)
        XCTAssertTrue(cached.eligibleGroups.isEmpty)
        options.outputRoot=clear
        let combined=try await BatchPlanComposer().combine(components:[.dates:cached],request:request,options:options)
        XCTAssertEqual(combined.eligibleGroups.count,1,combined.groups.flatMap(\.blockingReasons).joined(separator:"\n"))
        XCTAssertEqual(combined.groups.first?.items.first?.name.finalURL.path,clear.appendingPathComponent("original.jpg").path)
    }

}
