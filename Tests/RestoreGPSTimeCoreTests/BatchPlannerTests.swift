import XCTest
@testable import RestoreGPSTimeCore

class PlanningTestCase:NamingTestCase {
    let identity=DependencyIdentity(engineHash:"test-engine",databaseHash:"test-db",capabilityHash:"test-policy")
    func options(mode:SaveMode = .saveCopies) throws -> BatchOptions {
        var options=BatchOptions();options.mode=mode;options.outputRoot=try destination().root;options.recoveryRoot=workspace.appendingPathComponent("recovery");return options
    }
    func planner(now:Date=Date(timeIntervalSince1970:1_700_000_000))->BatchPlanner {BatchPlanner(dependencies:identity,clock:FixedClock(now))}
    func preview(_ item:InspectedItem,request:OperationRequest=OperationRequest(),mode:SaveMode = .saveCopies) async throws -> BatchPlan {try await planner().preview(items:[item],request:request,options:options(mode:mode))}
}
final class BatchPlannerTests:PlanningTestCase {
    func testPreviewNeverMutatesSource() async throws {
        let input=try item("a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        let plan=try await preview(input)
        XCTAssertEqual(plan.eligibleGroups.count,1)
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(plan.groups.first?.items.first).name.finalURL.path))
        XCTAssertEqual(plan,try JSONDecoder().decode(BatchPlan.self,from:JSONEncoder().encode(plan)))
    }
    func testOptionsInvalidatePreview() async throws {
        let input=try item("a.HEIC");var request=OperationRequest();request.dates=DatePolicy();request.dates?.timeZoneID="UTC"
        let a=try await preview(input,request:request)
        request.dates?.timeZoneID="Europe/Paris";let b=try await preview(input,request:request)
        request.placeOverrides[input.snapshot.id.physicalKey]=PlaceMatch(city:"Lyon",country:"France")
        let c=try await preview(input,request:request)
        XCTAssertNotEqual(a.optionsDigest,b.optionsDigest);XCTAssertNotEqual(b.optionsDigest,c.optionsDigest)
    }
    func testUnsupportedCompoundOperationBlocksGroup() async throws {
        let a=try item("a.HEIC",id:"pair"),b=try item("a.MOV",family:.video,id:"pair"),independent=try item("b.HEIC")
        var request=OperationRequest();request.tags=[.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("new"))];request.rename=NameTemplate()
        let plan=try await planner().preview(items:[a,b,independent],request:request,options:options())
        XCTAssertEqual(plan.groups.count,2);XCTAssertTrue(plan.groups.allSatisfy {$0.eligibility == .blocked})
        XCTAssertEqual(Set(plan.groups.flatMap(\.items).map {$0.name.finalURL.path}).count,3)
    }
    func testSidecarRequiresExplicitChoice() async throws {
        var request=OperationRequest();request.location=LocationWriteOptions()
        let input=try item("a.MKV",family:.video)
        let embedded=try await preview(input,request:request)
        XCTAssertEqual(embedded.groups.first?.eligibility,.blocked)
        XCTAssertFalse(embedded.groups.flatMap(\.items).contains {$0.mutation.outputKind == .xmpSidecar})
        request.metadataDestination = .xmpSidecar
        let sidecar=try await preview(input,request:request)
        XCTAssertTrue(sidecar.groups.flatMap(\.items).contains {$0.mutation.outputKind == .xmpSidecar})
    }
    func testCurrentTimeAndOrderingAreFrozen() async throws {
        var request=OperationRequest();request.dates=DatePolicy();request.dates?.source = .current
        let plan=try await planner().preview(items:[item("b.HEIC"),item("a.HEIC")],request:request,options:options())
        XCTAssertEqual(plan.groups.map {$0.items[0].source.snapshot.url.lastPathComponent},["a.HEIC","b.HEIC"])
        XCTAssertEqual(Set(plan.groups.flatMap(\.items).compactMap {$0.mutation.dates?.creationDate}),[plan.frozenNow])
    }
    func testLinkedSidecarUsesCaptureOfPrimary() async throws {
        var photo=try item("IMG.HEIC",id:"pair")
        photo=InspectedItem(snapshot:photo.snapshot,metadata:MetadataDocument(tags:["Apple:ContentIdentifier":.string("pair"),"ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05+02:00")],profile:photo.metadata.profile),place:photo.place)
        let video=try item("IMG.MOV",family:.video,id:"pair"),sidecar=try item("IMG.xmp",family:.unknown)
        var request=OperationRequest();request.dates=DatePolicy()
        let plan=try await planner().preview(items:[photo,video,sidecar],request:request,options:options())
        // The media member with no date remains a visible block; the sidecar uses primary provenance.
        let plannedSidecar=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.source.snapshot.url.pathExtension=="xmp"})
        XCTAssertEqual(plannedSidecar.resolution?.instant,try utc("2024-01-02T01:04:05Z"))
        XCTAssertNotNil(plannedSidecar.mutation.dates?.creationDate)
    }
    func testValidIndependentGroupsRemainEligible() async throws {
        let a=try item("a.HEIC"),b=try item("b.HEIC")
        let date=DateResolution(source:"test",original:"test",instant:try utc("2024-01-02T01:04:05Z"),offsetSeconds:0,fractionalPrecision:0,interpretation:"test",warnings:[])
        let valid=InspectedItem(snapshot:a.snapshot,metadata:MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 01:04:05Z")],profile:a.metadata.profile),dateResolution:date,place:a.place)
        var request=OperationRequest();request.dates=DatePolicy();request.rename=NameTemplate()
        let plan=try await planner().preview(items:[b,valid],request:request,options:options())
        XCTAssertEqual(plan.eligibleGroups.count,1);XCTAssertEqual(plan.groups.filter {$0.eligibility == .blocked}.count,1)
        XCTAssertEqual(Set(plan.groups.flatMap(\.items).map {$0.name.finalURL.path}).count,2)
    }
    func testNewOutputCannotChangeSelectedSourceDirectory() async throws {
        let file=try item("source/a.HEIC"),folder=file.snapshot.url.deletingLastPathComponent()
        let selected=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folder),metadata:MetadataDocument(tags:[:]))
        var settings=try options();settings.outputRoot=folder.appendingPathComponent("new-output")
        do {_ = try await planner().preview(items:[selected,file],request:OperationRequest(),options:settings);XCTFail("Creating this output would change an imported directory")} catch let error as RestoreError {XCTAssertEqual(error.code,.conflict)}
        XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(settings.outputRoot).path))
    }
    func testTrashCannotCombineWithOtherMutations() async throws {
        var request=OperationRequest();request.trashHiddenFiles=true;request.removeGPS=true
        do {_ = try await preview(item("a.HEIC"),request:request,mode:.modifyInPlace);XCTFail("Combined Trash must fail")} catch let error as RestoreError {XCTAssertEqual(error.code,.invalidInput)}
    }
}
