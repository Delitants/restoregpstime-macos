import XCTest
@testable import RestoreGPSTimeCore

final class CrashRecoveryTests:TransactionTestCase {
    func testCrashAtEveryPersistedPhase() async throws {
        for phase in [RecoveryPhase.prepared,.backedUp,.staged,.verified,.committing,.committed] {
            let input=try item("\(phase.rawValue)/a.HEIC"),plan=try await transactionPlan([input]),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
            let report=try await requireReport(plan,faults:TransactionFaults(.persisted(phase),crash:true))
            XCTAssertFalse(report.success,"Injected crash at \(phase)")
            let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),records=try journal.records()
            XCTAssertEqual(records.count,1);XCTAssertEqual(records.first?.phase,phase)
            let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
            XCTAssertTrue(outcome.isComplete,"\(phase): \(outcome.conflicts)")
            let after=try FileIdentityReader().fingerprint(at:input.snapshot.url)
            XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertEqual(after.snapshot.modificationDate,before.snapshot.modificationDate)
        }
    }
    func testCrashBetweenEveryCommitStep() async throws {
        for (rename,steps) in [(false,[CommitStep.swapPending,.swapped,.flagsPending,.complete]),(true,[CommitStep.publishPending,.published,.retirePending,.retired,.flagsPending,.complete])] {
            for step in steps {
                let input=try item("steps-\(rename)-\(step.rawValue)/a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),plan=try await transactionPlan([input],rename:rename)
                let report=try await requireReport(plan,faults:TransactionFaults(.persistedStep(step,index:0),crash:true))
                XCTAssertFalse(report.success)
                let record=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
                XCTAssertEqual(record.members.first?.step,step)
                let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
                XCTAssertTrue(outcome.isComplete,"\(rename)/\(step): \(outcome.conflicts)")
                let after=try FileIdentityReader().fingerprint(at:input.snapshot.url)
                XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertEqual(after.snapshot.modificationDate,before.snapshot.modificationDate)
                if rename,let final=plan.groups.first?.items.first?.name.finalURL {XCTAssertFalse(FileManager.default.fileExists(atPath:final.path))}
            }
        }
    }
    func testDiskFullAndJournalSyncFailure() async throws {
        let input=try item("a.HEIC"),plan=try await transactionPlan([input]),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        let failed=try await requireReport(plan,faults:TransactionFaults(.beforeJournalSync))
        XCTAssertFalse(failed.success);XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        let full=TransactionFaults();full.callback={point in if case .beforeBackup=point {throw NSError(domain:NSPOSIXErrorDomain,code:28)}}
        let noSpace=try await requireReport(plan,faults:full)
        XCTAssertFalse(noSpace.success);XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        XCTAssertFalse(full.points.contains {if case .beforeStage=$0 {return true};return false})
    }
}
