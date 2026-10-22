import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class ExternalEditRaceTests:TransactionTestCase {
    private let newer=Data("Newer external work; never restore the older vault over this version.\n".utf8)
    private func overwrite(_ url:URL,atomic:Bool) throws {
        if atomic {try newer.write(to:url,options:.atomic)}
        else {let handle=try FileHandle(forWritingTo:url);defer {try? handle.close()};try handle.truncate(atOffset:0);try handle.write(contentsOf:newer);try handle.synchronize()}
    }
    private func newerFiles() throws -> [URL] {
        guard let entries=FileManager.default.enumerator(at:workspace,includingPropertiesForKeys:[.isRegularFileKey]) else {return []}
        var matches=[URL]()
        for case let url as URL in entries where (try? url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true {if (try? Data(contentsOf:url))==newer {matches.append(url)}}
        return matches
    }
    private func assertRetainedConflict(_ plan:BatchPlan,report:BatchReport) async throws {
        XCTAssertEqual(report.results.first?.status,.recoveryNeeded,"A noncooperative edit cannot become success or a silent old-vault rollback.")
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=try XCTUnwrap(journal.records().first)
        XCTAssertEqual(record.phase,.recoveryNeeded);XCTAssertFalse(record.members.contains(where:\.restored))
        let held=try newerFiles();XCTAssertFalse(held.isEmpty,"The newer external payload must remain available.")
        let recovery=RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver())
        let outcome=try await recovery.restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete,"Explicit original-location recovery must also refuse an unknown held version.")
        XCTAssertFalse(try journal.records().contains {$0.members.contains(where:\.restored)})
        let separate=try await recovery.restore(batchID:plan.id,choice:.separateFolder(workspace.appendingPathComponent("Separate-"+plan.id.uuidString)))
        XCTAssertTrue(separate.isComplete,separate.conflicts.joined(separator:"\n"))
        for url in held {XCTAssertEqual(try Data(contentsOf:url),newer,"Separate recovery cannot move or replace newer work.")}
    }
    func testEditAndReplacementAtSwapPendingBlockStaleVaultRestore() async throws {
        for atomic in [false,true] {
            let input=try item("swap-\(atomic)/a.HEIC"),plan=try await transactionPlan([input]),faults=TransactionFaults()
            faults.callback={point in if point == .persistedStep(.swapPending,index:0) {try self.overwrite(input.snapshot.url,atomic:atomic)}}
            try await assertRetainedConflict(plan,report:requireReport(plan,faults:faults))
        }
    }
    func testEditAtRenameRetirementIsNotReportedCommitted() async throws {
        for atomic in [false,true] {
            let input=try item("rename-\(atomic)/a.HEIC"),plan=try await transactionPlan([input],rename:true),faults=TransactionFaults()
            faults.callback={point in if point == .persistedStep(.retirePending,index:0) {try self.overwrite(input.snapshot.url,atomic:atomic)}}
            try await assertRetainedConflict(plan,report:requireReport(plan,faults:faults))
        }
    }
    func testCrashAfterSwapOrRetireStillValidatesActualHeldOriginal() async throws {
        for rename in [false,true] {
            let input=try item("crash-\(rename)/a.HEIC"),plan=try await transactionPlan([input],rename:rename),faults=TransactionFaults(.persistedStep(rename ? .retired:.swapped,index:0),crash:true)
            faults.callback={point in if point == .persistedStep(rename ? .retirePending:.swapPending,index:0) {try self.overwrite(input.snapshot.url,atomic:true)}}
            let report=try await requireReport(plan,faults:faults)
            XCTAssertEqual(report.results.first?.status,.recoveryNeeded)
            let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
            XCTAssertFalse(outcome.isComplete);XCTAssertFalse(try newerFiles().isEmpty)
            let record=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
            XCTAssertFalse(record.members.contains(where:\.restored))
        }
    }
    func testCaseOnlyRetirementChecksNewerHeldVersion() async throws {
        for atomic in [false,true] {
            let input=try item("case-\(atomic)/a.HEIC"),base=try await transactionPlan([input])
            var request=base.request;request.rename=NameTemplate("A.{extension}")
            let plan=try await planner().preview(items:[input],request:request,options:base.options)
            guard plan.groups.first?.items.first?.name.needsTemporaryRename==true else {throw XCTSkip("Native case-only retirement requires a case-insensitive test volume; this volume must be recorded separately.")}
            let faults=TransactionFaults()
            faults.callback={point in if point == .persistedStep(.retirePending,index:0) {try self.overwrite(input.snapshot.url,atomic:atomic)}}
            try await assertRetainedConflict(plan,report:requireReport(plan,faults:faults))
        }
    }
    func testRenamedGroupPreflightProtectsNewerOldNameBeforeRetirement() async throws {
        let first=try item("rename-compound/a.HEIC"),second=try item("rename-compound/b.MOV",family:.video),base=try await transactionPlan([first,second],rename:true)
        var request=base.request;request.groups.forcedGroups=[[first.snapshot.id.physicalKey,second.snapshot.id.physicalKey]]
        let plan=try await planner().preview(items:[first,second],request:request,options:base.options),group=try XCTUnwrap(plan.groups.first)
        XCTAssertEqual(group.eligibility,.eligible,group.blockingReasons.joined(separator:"\n"))
        let source=group.items[1].source.snapshot.url,faults=TransactionFaults(.persistedStep(.retirePending,index:1),crash:true)
        faults.callback={point in if point == .persistedStep(.retirePending,index:1) {try self.overwrite(source,atomic:true)}}
        let report=try await requireReport(plan,faults:faults);XCTAssertEqual(report.results.first?.status,.recoveryNeeded)
        let targets=try group.items.map {try FileIdentityReader().fingerprint(at:$0.name.finalURL)}
        let result=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(result.isComplete);XCTAssertEqual(try Data(contentsOf:source),newer)
        let record=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
        XCTAssertFalse(record.members.contains(where:\.restored))
        for (item,target) in zip(group.items,targets) {XCTAssertEqual(try FileIdentityReader().fingerprint(at:item.name.finalURL),target,"Preflight must stop before moving an earlier group member.")}
    }
    func testCompoundPreflightDoesNotRestoreEarlierMemberWhenLaterOriginalDiverged() async throws {
        let first=try item("compound/a.HEIC"),second=try item("compound/b.HEIC"),base=try await transactionPlan([first,second])
        var request=base.request;request.groups.forcedGroups=[[first.snapshot.id.physicalKey,second.snapshot.id.physicalKey]]
        let plan=try await planner().preview(items:[first,second],request:request,options:base.options),group=try XCTUnwrap(plan.groups.first)
        XCTAssertEqual(group.items.count,2)
        let source=group.items[1].source.snapshot.url,faults=TransactionFaults()
        faults.callback={point in if point == .persistedStep(.swapPending,index:1) {try self.overwrite(source,atomic:true)}}
        try await assertRetainedConflict(plan,report:requireReport(plan,faults:faults))
    }
}
