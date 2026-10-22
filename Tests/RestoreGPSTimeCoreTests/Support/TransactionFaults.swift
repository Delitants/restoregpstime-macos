import Foundation
import Darwin
import XCTest
@testable import RestoreGPSTimeCore

final class TransactionFaults:@unchecked Sendable {
    let lock=NSLock()
    var points=[TransactionPoint]()
    var failAt:TransactionPoint?
    var crash=false
    var callback:((TransactionPoint)throws->Void)?
    init(_ point:TransactionPoint?=nil,crash:Bool=false) {failAt=point;self.crash=crash}
    func check(_ point:TransactionPoint) throws {
        lock.lock();points.append(point);let matches=failAt==point;let callback=self.callback;lock.unlock()
        try callback?(point)
        if matches {if crash {throw SimulatedInterruption()};throw RestoreError(.io,"Injected I/O failure at \(point)")}
    }
}
struct TransactionTestDriver:MutationDriver {
    let hook:@Sendable(URL)throws->Void
    init(hook:@escaping @Sendable(URL)throws->Void={_ in}) {self.hook=hook}
    func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification {
        try Task.checkCancellation();try hook(stage)
        if let date=mutation.dates?.modificationDate {try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:stage.path)}
        return .init(contentHash:try FileIdentityReader().fingerprint(at:stage).contentHash,integrityValidator:"sha256-v1")
    }
    func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws {
        let fd=open(stage.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw SecureFS.error("Open fixture restore stage")};defer {close(fd)}
        try SecureFS.dates(snapshot,fd:fd)
    }
}
class TransactionTestCase:PlanningTestCase {
    var recoveryRoot:URL {workspace.appendingPathComponent("Recovery")}
    func transactionPlan(_ inputs:[InspectedItem],mode:SaveMode = .modifyInPlace,rename:Bool=false) async throws -> BatchPlan {
        var request=OperationRequest();var dates=DatePolicy();dates.source = .specific(try utc("2020-02-03T04:05:06Z"));dates.targets = .modification;request.dates=dates
        if rename {request.rename=NameTemplate()}
        var settings=try options(mode:mode);settings.recoveryRoot=recoveryRoot
        return try await planner().preview(items:inputs,request:request,options:settings)
    }
    func run(_ plan:BatchPlan,faults:TransactionFaults=TransactionFaults(),driver:TransactionTestDriver=TransactionTestDriver()) async -> BatchReport? {
        let identity=self.identity,executor=BatchExecutor(driver:driver,validator:.init(dependencies:{identity}))
        var report:BatchReport?
        for await event in executor.execute(plan,options:.init(checkpoint:faults.check)) {if case .finished(let result)=event {report=result}}
        return report
    }
    func requireReport(_ plan:BatchPlan,faults:TransactionFaults=TransactionFaults(),driver:TransactionTestDriver=TransactionTestDriver()) async throws -> BatchReport {
        let report=await run(plan,faults:faults,driver:driver)
        if let report {try JSONEncoder().encode(report).write(to:workspace.appendingPathComponent("report-\(plan.id.uuidString)-\(UUID().uuidString).json"))}
        return try XCTUnwrap(report)
    }
    override func tearDownWithError() throws {
        if (testRun?.totalFailureCount ?? 0)>0,let workspace {
            let evidence=repository.appendingPathComponent("work/failed-transactions/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at:evidence.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.moveItem(at:workspace,to:evidence)
            self.workspace=nil
        }
        try super.tearDownWithError()
    }
}
