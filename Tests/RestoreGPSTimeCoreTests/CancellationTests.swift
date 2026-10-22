import XCTest
@testable import RestoreGPSTimeCore

final class CancellationTests:TransactionTestCase {
    func testCancellationWaitsForProtectedCommit() async throws {
        let a=try item("a.HEIC"),b=try item("b.HEIC"),before=try FileIdentityReader().fingerprint(at:b.snapshot.url),plan=try await transactionPlan([a,b]),identity=self.identity
        let executor=BatchExecutor(driver:TransactionTestDriver(),validator:PlanValidator(dependencies:{identity}))
        let options=RunOptions {point in
            if point == .afterMember(0) {
                let semaphore=DispatchSemaphore(value:0)
                Task {await executor.cancel(batchID:plan.id);semaphore.signal()}
                XCTAssertEqual(semaphore.wait(timeout:.now()+5),.success)
            }
        }
        var report:BatchReport?
        for await event in executor.execute(plan,options:options) {if case .finished(let result)=event {report=result}}
        let final=try XCTUnwrap(report)
        XCTAssertTrue(final.cancelled);XCTAssertEqual(final.results.map(\.status),[.committed,.cancelled])
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:b.snapshot.url))
    }
    func testCancelDuringStageAndCommit() async throws {
        let input=try item("a.HEIC"),plan=try await transactionPlan([input]),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        let faults=TransactionFaults();faults.callback={point in if case .beforeStage=point {throw CancellationError()}}
        let report=try await requireReport(plan,faults:faults)
        XCTAssertTrue(report.cancelled);XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
    }
}
