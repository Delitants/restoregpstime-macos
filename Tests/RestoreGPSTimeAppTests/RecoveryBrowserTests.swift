import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class RecoveryBrowserTests:AppTestCase {
    func testBrowsingMissingRootDoesNotCreateIt() async throws {
        let missing=workspace.appendingPathComponent("Missing")
        let entries=try await RecoveryBrowser().scan(root:missing)
        XCTAssertTrue(entries.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }
    func testBrowserListsSavedPhasesAndRejectsSymlinkManifests() async throws {
        let input=try item(),output=workspace.appendingPathComponent("Output"),root=workspace.appendingPathComponent("Recovery")
        var options=BatchOptions();options.outputRoot=output;options.recoveryRoot=root
        var request=OperationRequest();request.dates=DatePolicy()
        let plan=try await BatchPlanner(dependencies:.init(engineHash:"test",databaseHash:"test",capabilityHash:"test")).preview(items:[input],request:request,options:options)
        let journal=try RecoveryJournal(root:root,batchID:plan.id),group=try XCTUnwrap(plan.groups.first)
        var record=RecoveryRecord(batchID:plan.id,group:group,options:options);record.phase = .recoveryNeeded
        try journal.persist(record)
        let laterID=UUID(),laterJournal=try RecoveryJournal(root:root,batchID:laterID)
        var later=RecoveryRecord(batchID:laterID,group:group,options:options);later.phase = .committed
        try laterJournal.persist(later)
        let entries=try await RecoveryBrowser().scan(root:root)
        XCTAssertEqual(entries.count,2);XCTAssertEqual(entries.first?.incompleteGroups,1);XCTAssertEqual(entries.first?.batchID,plan.id)
        let manifest=journal.recordURL(groupID:group.id),retained=workspace.appendingPathComponent("retained.json")
        try FileManager.default.moveItem(at:manifest,to:retained);try FileManager.default.createSymbolicLink(at:manifest,withDestinationURL:retained)
        do {_ = try await RecoveryBrowser().scan(root:root);XCTFail("Linked journal must be rejected") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath:retained.path))
    }
    func testCatalogueExposesPerFileBackupModeAndCompletedNoBackupCannotUndo() async throws {
        let input=try item(),root=workspace.appendingPathComponent("Recovery")
        var options=BatchOptions();options.mode = .modifyInPlace;options.backupMode=BackupMode.none;options.recoveryRoot=root
        var request=OperationRequest();request.dates=DatePolicy()
        let plan=try await BatchPlanner(dependencies:.init(engineHash:"test",databaseHash:"test",capabilityHash:"test")).preview(items:[input],request:request,options:options)
        let journal=try RecoveryJournal(root:root,batchID:plan.id),group=try XCTUnwrap(plan.groups.first)
        var record=RecoveryRecord(batchID:plan.id,group:group,options:options);record.phase = .committed
        try journal.persist(record)
        let scanned=try await RecoveryBrowser().scan(root:root)
        let batch=try XCTUnwrap(scanned.first)
        XCTAssertEqual(batch.files.count,1);XCTAssertEqual(batch.files.first?.backupMode,BackupMode.none)
        XCTAssertEqual(batch.files.first?.sourceKey,input.snapshot.id.physicalKey)
        XCTAssertFalse(batch.files.first?.canUndo ?? true)
    }

}
