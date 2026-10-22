import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class InPlaceTests:TransactionTestCase {
    func testBackupBeforeFirstMutation() async throws {
        let a=try item("a.HEIC",id:"pair"),b=try item("a.MOV",family:.video,id:"pair")
        let plan=try await transactionPlan([a,b]),root=recoveryRoot
        let driver=TransactionTestDriver {stage in
            XCTAssertFalse([a.snapshot.url.path,b.snapshot.url.path].contains(stage.path))
            let journal=try RecoveryJournal(root:root,batchID:plan.id)
            let record=try XCTUnwrap(journal.records().first)
            XCTAssertTrue(record.members.allSatisfy {$0.backupURL != nil && $0.backupHash != nil})
            for member in record.members {XCTAssertEqual(try Data(contentsOf:try XCTUnwrap(member.backupURL)),try Data(contentsOf:member.item.source.snapshot.url))}
        }
        let report=try await requireReport(plan,driver:driver);XCTAssertTrue(report.success)
    }
    func testExternalEditBeforeCommit() async throws {
        let input=try item("a.HEIC"),plan=try await transactionPlan([input]),faults=TransactionFaults()
        faults.callback={point in if point == .beforeCommit {try Data("external edit".utf8).write(to:input.snapshot.url)}}
        let report=try await requireReport(plan,faults:faults)
        XCTAssertFalse(report.success);XCTAssertEqual(try Data(contentsOf:input.snapshot.url),Data("external edit".utf8))
    }
    func testRecoveryNeverOverwritesNewerEdit() async throws {
        let input=try item("a.HEIC"),plan=try await transactionPlan([input],rename:true)
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let target=try XCTUnwrap(report.results.first?.outputs.first)
        try Data("newer edit".utf8).write(to:target)
        let recovery=RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver())
        let original=try await recovery.restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(original.isComplete);XCTAssertEqual(try Data(contentsOf:target),Data("newer edit".utf8))
        let copy=try await recovery.restore(batchID:plan.id,choice:.separateFolder(workspace.appendingPathComponent("restored")))
        XCTAssertTrue(copy.isComplete);XCTAssertEqual(copy.restored.count,1)
        XCTAssertEqual(try Data(contentsOf:try XCTUnwrap(copy.restored.first)),Data("payload-a.HEIC".utf8))
    }
    func testFailedSeparateRestoreDoesNotPublishPartial() async throws {
        struct FailedRestore:MutationDriver {
            func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification {throw RestoreError(.io,"Not used")}
            func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws {throw RestoreError(.io,"Injected restore attribute failure")}
        }
        let input=try item("a.HEIC"),plan=try await transactionPlan([input]),report=try await requireReport(plan)
        XCTAssertTrue(report.success)
        let output=workspace.appendingPathComponent("failed-separate")
        let result=try await RecoveryCoordinator(root:recoveryRoot,driver:FailedRestore()).restore(batchID:plan.id,choice:.separateFolder(output))
        XCTAssertFalse(result.isComplete);XCTAssertTrue(result.restored.isEmpty)
        let final=output.appendingPathComponent(plan.id.uuidString).appendingPathComponent(plan.groups[0].id.uuidString).appendingPathComponent("a.HEIC")
        XCTAssertFalse(FileManager.default.fileExists(atPath:final.path))
    }
    func testGroupFailureRestoresLinkedMembers() async throws {
        let a=try item("a.HEIC",id:"pair"),b=try item("a.MOV",family:.video,id:"pair"),plan=try await transactionPlan([a,b],rename:true)
        let before=try [a,b].map {try FileIdentityReader().fingerprint(at:$0.snapshot.url)}
        let report=try await requireReport(plan,faults:TransactionFaults(.afterMember(0)))
        XCTAssertFalse(report.success)
        for (item,expected) in zip([a,b],before) {
            let after=try FileIdentityReader().fingerprint(at:item.snapshot.url)
            XCTAssertEqual(after.contentHash,expected.contentHash);XCTAssertEqual(after.snapshot.modificationDate,expected.snapshot.modificationDate)
        }
    }
    func testACLResourceForkAndExplicitUnlock() async throws {
        let initial=try item("attributes.HEIC"),path=initial.snapshot.url.path
        let chmod=Process();chmod.executableURL=URL(fileURLWithPath:"/bin/chmod");chmod.arguments=["+a",NSUserName()+" allow read,write",path];try chmod.run();chmod.waitUntilExit();XCTAssertEqual(chmod.terminationStatus,0)
        let value=Data("synthetic resource fork".utf8)
        XCTAssertEqual(value.withUnsafeBytes {setxattr(path,"com.apple.ResourceFork",$0.baseAddress,value.count,0,XATTR_NOFOLLOW)},0)
        XCTAssertEqual(chflags(path,UInt32(UF_IMMUTABLE)),0)
        defer {_ = chflags(path,0)}
        let locked=try item("attributes.HEIC"),blocked=try await transactionPlan([locked])
        XCTAssertEqual(blocked.groups.first?.eligibility,.blocked)
        var request=OperationRequest();request.finder=[.locked(false)];var policy=DatePolicy();policy.source = .specific(try utc("2020-02-03T04:05:06Z"));policy.targets = .modification;request.dates=policy
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot
        let plan=try await planner().preview(items:[locked],request:request,options:settings)
        let report=try await requireReport(plan);XCTAssertTrue(report.success,"\(report.results)")
        let after=try FileIdentityReader().snapshot(at:initial.snapshot.url)
        XCTAssertFalse(after.isLocked);XCTAssertEqual(after.permissions,locked.snapshot.permissions);XCTAssertEqual(after.aclText,locked.snapshot.aclText);XCTAssertEqual(after.xattrHashes,locked.snapshot.xattrHashes)
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
        XCTAssertTrue(try FileIdentityReader().snapshot(at:initial.snapshot.url).isLocked)
    }
    func testFolderDatesAfterChildrenAndRecovery() async throws {
        let child=try item("folder/child.HEIC"),folderURL=child.snapshot.url.deletingLastPathComponent()
        let folder=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folderURL),metadata:MetadataDocument(tags:[:]))
        let plan=try await transactionPlan([folder,child]),before=folder.snapshot.modificationDate
        let report=try await requireReport(plan)
        XCTAssertTrue(report.success,"\(report.results)")
        XCTAssertEqual(try FileIdentityReader().snapshot(at:folderURL).modificationDate,try utc("2020-02-03T04:05:06Z"))
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
        XCTAssertEqual(try FileIdentityReader().snapshot(at:folderURL).modificationDate,before)
        let again=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(again.isComplete,"\(again.conflicts)")
    }
    func testHardlinksSymlinksACLsAndLocks() async throws {
        let input=try item("a.HEIC")
        try FileManager.default.createSymbolicLink(at:workspace.appendingPathComponent("link"),withDestinationURL:input.snapshot.url)
        try FileManager.default.linkItem(at:input.snapshot.url,to:workspace.appendingPathComponent("hardlink"))
        let plan=try await transactionPlan([item("a.HEIC")])
        let report=try await requireReport(plan);XCTAssertFalse(report.success)
        XCTAssertEqual(try Data(contentsOf:input.snapshot.url),Data("payload-a.HEIC".utf8))
    }
}
