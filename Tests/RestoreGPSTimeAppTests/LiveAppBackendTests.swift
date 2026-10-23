import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class LiveAppBackendTests:AppTestCase {
    func testBatchedImportReportsCountsAndKeepsAFileErrorIsolated() async throws {
        let backend=try backend(),recorder=AppPreparationRecorder()
        var urls=[URL]()
        for index in 0..<65 {
            let url=workspace.appendingPathComponent("Photo-\(index).jpg")
            if index==64 {try Data().write(to:url)}
            else {try FileManager.default.copyItem(at:repo.appendingPathComponent("Tests/Fixtures/paris.jpg"),to:url)}
            urls.append(url)
        }
        let before=try urls.map {try FileIdentityReader().fingerprint(at:$0)}
        let result=try await backend.inspectDetailed(urls,options:DiscoveryOptions(),progress:{await recorder.append($0)})
        XCTAssertEqual(result.items.count,65)
        XCTAssertEqual(result.items.filter {$0.metadata.profile.identifier=="JPEG"}.count,64)
        XCTAssertEqual(result.items.filter {!$0.metadata.diagnostics.isEmpty}.count,1)
        let metadata=await recorder.events.filter {$0.stage == .metadata}
        XCTAssertEqual(metadata.first?.completed,0);XCTAssertEqual(metadata.last?.completed,65)
        XCTAssertTrue(metadata.contains {$0.completed>0 && $0.completed<65});XCTAssertTrue(metadata.allSatisfy {$0.total==65})
        XCTAssertEqual(try urls.map {try FileIdentityReader().fingerprint(at:$0)},before)
    }
    private var repo:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func backend() throws -> LiveAppBackend {
        let bundle=ProcessInfo.processInfo.environment["RESTOREGPSTIME_TEST_APP_BUNDLE"].map {URL(fileURLWithPath:$0)} ?? repo.appendingPathComponent("work/test-bundles/arm64-ui-t10a/RestoreGPSTime.app")
        return LiveAppBackend(paths:try RuntimeLocator().locate(in:bundle))
    }
    @MainActor func testLiveHEICPhotoAndVideoCopyPreviewUsesOfflinePlacesAndRetainsSources() async throws {
        let model=AppModel(backend:try backend())
        let inputs=workspace.appendingPathComponent("Inputs");try FileManager.default.createDirectory(at:inputs,withIntermediateDirectories:true)
        var urls=[URL](),before=[SourceFingerprint]()
        for name in ["paris.jpg","paris.heic","paris.mov"] {
            let target=inputs.appendingPathComponent(name);try FileManager.default.copyItem(at:repo.appendingPathComponent("Tests/Fixtures/"+name),to:target)
            urls.append(target);before.append(try FileIdentityReader().fingerprint(at:target))
        }
        model.options.outputRoot=workspace.appendingPathComponent("Output");model.options.recoveryRoot=workspace.appendingPathComponent("Recovery")
        model.request.location=LocationWriteOptions();model.request.rename=NameTemplate();model.request.dates?.quickTime = .utc
        await model.importURLs([inputs]);XCTAssertEqual(model.rows.count,3)
        await model.preview();XCTAssertTrue(model.canApply,model.rows.compactMap(\.issue).joined(separator:"\n"))
        XCTAssertTrue(model.rows.allSatisfy {$0.planned?.place?.origin == .database})
        XCTAssertTrue(model.rows.allSatisfy {$0.planned?.name.finalURL.lastPathComponent.contains("Paris")==true})
        await model.applyPreview();let report=try XCTUnwrap(model.report)
        XCTAssertTrue(report.success,report.results.flatMap(\.errors).joined(separator:"\n"))
        XCTAssertEqual(report.results.flatMap(\.outputs).count,3)
        for (index,url) in urls.enumerated() {XCTAssertEqual(try FileIdentityReader().fingerprint(at:url),before[index])}
        for output in report.results.flatMap(\.outputs) {XCTAssertTrue(FileManager.default.fileExists(atPath:output.path))}
        let entries=try await RecoveryBrowser().scan(root:try XCTUnwrap(model.options.recoveryRoot));XCTAssertEqual(entries.count,1)
    }
    @MainActor func testLiveInPlaceAndExplicitRecoveryReturnOriginalBytesAndAttributes() async throws {
        let url=workspace.appendingPathComponent("Original.jpg");try FileManager.default.copyItem(at:repo.appendingPathComponent("Tests/Fixtures/paris.jpg"),to:url)
        let before=try FileIdentityReader().fingerprint(at:url),model=AppModel(backend:try backend())
        model.options.mode = .modifyInPlace;model.options.recoveryRoot=workspace.appendingPathComponent("Recovery")
        model.request.location=LocationWriteOptions();await model.importURLs([url]);await model.preview()
        XCTAssertTrue(model.canApply,model.rows.compactMap(\.issue).joined(separator:"\n"))
        await model.applyPreview();let report=try XCTUnwrap(model.report);XCTAssertTrue(report.success,report.results.flatMap(\.errors).joined(separator:"\n"))
        XCTAssertNotEqual(try FileIdentityReader().fingerprint(at:url).contentHash,before.contentHash)
        await model.restore(batchID:report.batchID,choice:.originalLocations)
        XCTAssertNil(model.issue);let after=try FileIdentityReader().fingerprint(at:url)
        XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertEqual(after.snapshot.xattrHashes,before.snapshot.xattrHashes)
        XCTAssertEqual(after.snapshot.creationDate.timeIntervalSince1970,before.snapshot.creationDate.timeIntervalSince1970,accuracy:0.000001)
    }
}
private actor AppPreparationRecorder {
    var events=[PreparationProgress]()
    func append(_ value:PreparationProgress) {events.append(value)}
}
