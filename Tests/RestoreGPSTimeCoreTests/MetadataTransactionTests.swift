import XCTest
@testable import RestoreGPSTimeCore

final class MetadataTransactionTests:TransactionTestCase {
    func testExplicitXMPSidecarThroughTransaction() async throws {
        let input=try await inspectedFixture("paris.jpg"),paths=try RuntimeLocator().locate(in:testApp),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        var request=OperationRequest();request.metadataDestination = .xmpSidecar
        request.tags=[.set(TagID(rawValue:"XMP-dc:Description-x-default")!,.string("Paris, France"))]
        let plan=try await preview(input,request:request)
        XCTAssertEqual(plan.eligibleGroups.count,1)
        let expected=self.identity,driver=MetadataMutationDriver(paths:paths),executor=BatchExecutor(driver:MetadataMutationDriver(paths:paths),validator:.init(dependencies:{expected}))
        var report:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let value)=event {report=value}}
        let completed=try XCTUnwrap(report);XCTAssertTrue(completed.success,"\(completed.results)")
        let output=try XCTUnwrap(completed.results.flatMap(\.outputs).first {$0.pathExtension=="xmp"})
        let doc=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:output))
        XCTAssertEqual(doc.tags["XMP-dc:Description"]?.text,"Paris, France")
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
    }
    func inspectedFixture(_ name:String) async throws -> InspectedItem {
        let url=workspace.appendingPathComponent(name)
        try FileManager.default.copyItem(at:fixture(name),to:url)
        let snapshot=try FileIdentityReader().snapshot(at:url)
        return InspectedItem(snapshot:snapshot,metadata:try await MetadataReader(paths:RuntimePaths(appBundle:testApp)).read(snapshot:snapshot))
    }
    func testPlannerQualifiesActualMediaAndTagScope() async throws {
        let real=try await inspectedFixture("paris.jpg"),fake=try item("fake.HEIC")
        var request=OperationRequest();request.tags=[.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("planned"))]
        let plan=try await planner().preview(items:[real,fake],request:request,options:options())
        XCTAssertEqual(plan.eligibleGroups.count,1)
        XCTAssertEqual(plan.groups.first(where:{$0.items[0].source.snapshot.url==fake.snapshot.url})?.eligibility,.blocked)
        request.tags=[.set(TagID(rawValue:"ExifIFD:MakerNote")!,.string("unqualified"))]
        let invalid=try await preview(real,request:request)
        XCTAssertEqual(invalid.groups[0].eligibility,.blocked)
    }
    func testMetadataCopiesAndInPlaceRestoreThroughTransactions() async throws {
        let paths=try RuntimeLocator().locate(in:testApp)
        for file in ["paris.jpg","paris.heic","paris.png","paris.tiff","paris.mov","geometric-baseline.webp","geometric-baseline.avif","geometric-baseline.mp4"] {
        let input=try await inspectedFixture(file)
        let before=try FileIdentityReader().fingerprint(at:input.snapshot.url),tag=TagID(rawValue:"XMP-dc:Description-x-default")!
        for mode in [SaveMode.saveCopies,.modifyInPlace] {
            var request=OperationRequest();request.tags=[.set(tag,.string("Transaction verified"))]
            let plan=try await planner().preview(items:[input],request:request,options:options(mode:mode))
            XCTAssertEqual(plan.eligibleGroups.count,1)
            let expected=self.identity,driver=MetadataMutationDriver(paths:paths)
            let executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
            var report:BatchReport?
            for await event in executor.execute(plan) {if case .finished(let value)=event {report=value}}
            let completed=try XCTUnwrap(report)
            try JSONEncoder().encode(completed).write(to:workspace.appendingPathComponent("metadata-report-\(file)-\(mode.rawValue).json"))
            XCTAssertTrue(completed.success,"\(completed.results)")
            let output=try XCTUnwrap(completed.results.first?.outputs.first)
            let after=try await MetadataReader(paths:paths).read(snapshot:FileIdentityReader().snapshot(at:output))
            XCTAssertEqual(TagRegistry().value(for:tag,in:after)?.text,"Transaction verified")
            if mode == .saveCopies {XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))}
            else {
                let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
                XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
                let actual=try FileIdentityReader().fingerprint(at:input.snapshot.url)
                XCTAssertEqual(actual.contentHash,before.contentHash)
                XCTAssertEqual(actual.snapshot.creationDate,before.snapshot.creationDate)
                XCTAssertEqual(actual.snapshot.modificationDate,before.snapshot.modificationDate)
                XCTAssertEqual(actual.snapshot.xattrHashes,before.snapshot.xattrHashes)
            }
        }
        }
    }
}
