import XCTest
@testable import RestoreGPSTimeCore

final class CopyModeTests:TransactionTestCase {
    func testCopiesPreserveSources() async throws {
        let input=try item("a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        let plan=try await transactionPlan([input],mode:.saveCopies),report=try await requireReport(plan)
        XCTAssertTrue(report.success);XCTAssertEqual(report.results.first?.outputs.count,1)
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        let final=try XCTUnwrap(report.results.first?.outputs.first)
        XCTAssertEqual(try Data(contentsOf:final),try Data(contentsOf:input.snapshot.url))
        XCTAssertEqual(try FileIdentityReader().snapshot(at:final).modificationDate,try utc("2020-02-03T04:05:06Z"))
    }
    func testCopyFoldersPreserveHierarchyAndSourceDates() async throws {
        let child=try item("folder/child.HEIC"),folderURL=child.snapshot.url.deletingLastPathComponent()
        let folder=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folderURL),metadata:MetadataDocument(tags:[:]))
        let before=try FileIdentityReader().fingerprint(at:folderURL)
        var request=OperationRequest();var date=DatePolicy();date.source = .specific(try utc("2020-02-03T04:05:06Z"));date.targets = .modification;request.dates=date
        var settings=try options();settings.importRoots=[folderURL];settings.recoveryRoot=recoveryRoot
        let plan=try await planner().preview(items:[folder,child],request:request,options:settings),report=try await requireReport(plan)
        XCTAssertTrue(report.success,"\(report.results)")
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:folderURL))
        let target=try XCTUnwrap(settings.outputRoot).appendingPathComponent("folder/child.HEIC")
        XCTAssertEqual(try Data(contentsOf:target),try Data(contentsOf:child.snapshot.url))
        XCTAssertEqual(try FileIdentityReader().snapshot(at:target.deletingLastPathComponent()).modificationDate,try utc("2020-02-03T04:05:06Z"))
    }
    func testDirectoryRaceDoesNotReplaceExternalAttributes() async throws {
        let child=try item("folder/child.HEIC"),folder=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:child.snapshot.url.deletingLastPathComponent()),metadata:MetadataDocument(tags:[:]))
        let plan=try await transactionPlan([folder],mode:.saveCopies),target=try XCTUnwrap(plan.groups.first?.items.first?.name.finalURL),externalDate=try utc("2010-01-02T03:04:05Z"),faults=TransactionFaults()
        faults.callback={point in if point == .persistedStep(.directoryPending,index:0) {try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false);try FileManager.default.setAttributes([.modificationDate:externalDate],ofItemAtPath:target.path)}}
        let report=try await requireReport(plan,faults:faults)
        XCTAssertFalse(report.success)
        XCTAssertEqual(try FileIdentityReader().snapshot(at:target).modificationDate,externalDate)
    }
    func testNoReplaceAtCommit() async throws {
        let plan=try await transactionPlan([item("a.HEIC")],mode:.saveCopies)
        let target=try XCTUnwrap(plan.groups.first?.items.first?.name.finalURL),faults=TransactionFaults()
        faults.callback={point in if point == .beforeCommit {try Data("external".utf8).write(to:target)}}
        let report=try await requireReport(plan,faults:faults)
        XCTAssertFalse(report.success);XCTAssertEqual(try Data(contentsOf:target),Data("external".utf8))
    }
}
