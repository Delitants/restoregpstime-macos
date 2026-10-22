import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class AttributeTransactionTests:TransactionTestCase {
    private func fixtureGroup(locked:Bool=false,folderName:String="folder") async throws -> [InspectedItem] {
        let folder=workspace.appendingPathComponent(folderName),file=folder.appendingPathComponent("child.jpg")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try FileManager.default.copyItem(at:fixture("paris.jpg"),to:file)
        if locked {XCTAssertEqual(chflags(folder.path,UInt32(UF_IMMUTABLE)),0)}
        let snapshot=try FileIdentityReader().snapshot(at:file),reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        return [InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folder),metadata:.init(tags:[:])),InspectedItem(snapshot:snapshot,metadata:try await reader.read(snapshot:snapshot))]
    }
    private func productionPlan(_ items:[InspectedItem],finder:[FinderMutation],mode:SaveMode = .modifyInPlace) async throws -> BatchPlan {
        var request=OperationRequest();var dates=DatePolicy();dates.source = .specific(try utc("2020-02-03T04:05:06Z"));dates.targets = .modification;request.dates=dates;request.finder=finder
        var settings=try options(mode:mode);settings.importRoots=[items[0].snapshot.url]
        return try await planner().preview(items:items,request:request,options:settings)
    }
    private func execute(_ plan:BatchPlan,driver:AttributeMutationDriver,faults:TransactionFaults=TransactionFaults()) async throws -> BatchReport {
        let expected=self.identity,executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
        var report:BatchReport?
        for await event in executor.execute(plan,options:.init(checkpoint:{try faults.check($0)})) {if case .finished(let result)=event {report=result}}
        let result=try XCTUnwrap(report)
        try JSONEncoder().encode(result).write(to:workspace.appendingPathComponent("attribute-report-\(plan.id.uuidString).json"));return result
    }
    func testFolderUnlockPrecedesChildrenAndRecoveryRestoresOriginalLock() async throws {
        let items=try await fixtureGroup(locked:true),folder=items[0].snapshot.url,file=items[1].snapshot.url
        defer {_ = chflags(folder.path,0);_ = chflags(file.path,0)}
        let plan=try await productionPlan(items,finder:[.locked(false)]),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let report=try await execute(plan,driver:driver)
        XCTAssertTrue(report.success,"\(report.results)");guard report.success else {return}
        XCTAssertFalse(try FileIdentityReader().snapshot(at:folder).isLocked)
        let recovery=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(recovery.isComplete,"\(recovery.conflicts)")
        XCTAssertTrue(try FileIdentityReader().snapshot(at:folder).isLocked)
        XCTAssertEqual(try FileIdentityReader().snapshot(at:folder).modificationDate,items[0].snapshot.modificationDate)
    }
    func testFinalFolderLockFollowsChildrenAndUnlocksForRestore() async throws {
        let items=try await fixtureGroup(),folder=items[0].snapshot.url,file=items[1].snapshot.url
        defer {_ = chflags(folder.path,0);_ = chflags(file.path,0)}
        let plan=try await productionPlan(items,finder:[.locked(true)]),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let report=try await execute(plan,driver:driver)
        XCTAssertTrue(report.success,"\(report.results)");guard report.success else {return}
        XCTAssertTrue(try FileIdentityReader().snapshot(at:folder).isLocked);XCTAssertTrue(try FileIdentityReader().snapshot(at:file).isLocked)
        let recovery=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(recovery.isComplete,"\(recovery.conflicts)")
        XCTAssertFalse(try FileIdentityReader().snapshot(at:folder).isLocked);XCTAssertFalse(try FileIdentityReader().snapshot(at:file).isLocked)
        let again=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(again.isComplete,"\(again.conflicts)")
    }
    func testNestedFinalLocksDoNotInvalidateAncestorDates() async throws {
        let innerItems=try await fixtureGroup(folderName:"outer/inner"),outer=workspace.appendingPathComponent("outer")
        let items=[InspectedItem(snapshot:try FileIdentityReader().snapshot(at:outer),metadata:.init(tags:[:]))]+innerItems
        defer {_ = chflags(outer.path,0);_ = chflags(innerItems[0].snapshot.url.path,0);_ = chflags(innerItems[1].snapshot.url.path,0)}
        let plan=try await productionPlan(items,finder:[.locked(true)]),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let report=try await execute(plan,driver:driver)
        XCTAssertTrue(report.success,"\(report.results)");guard report.success else {return}
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
        for item in items {XCTAssertFalse(try FileIdentityReader().snapshot(at:item.snapshot.url).isLocked)}
    }
    func testCancellationRestoresPreparedDirectoryLock() async throws {
        let items=try await fixtureGroup(locked:true),folder=items[0].snapshot.url,file=items[1].snapshot.url
        defer {_ = chflags(folder.path,0);_ = chflags(file.path,0)}
        let plan=try await productionPlan(items,finder:[.locked(false)]),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp)),expected=self.identity
        let executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected})),gate=DispatchSemaphore(value:0),faults=TransactionFaults()
        faults.callback={point in if point == .afterMember(0) {
            Task {await executor.cancel(batchID:plan.id);gate.signal()}
            guard gate.wait(timeout:.now()+3) == .success else {throw RestoreError(.io,"Fixture cancellation did not synchronize")}
        }}
        var report:BatchReport?
        for await event in executor.execute(plan,options:.init(checkpoint:{try faults.check($0)})) {if case .finished(let result)=event {report=result}}
        XCTAssertTrue(try XCTUnwrap(report).cancelled)
        XCTAssertTrue(try FileIdentityReader().snapshot(at:folder).isLocked)
        XCTAssertEqual(try FileIdentityReader().snapshot(at:folder).modificationDate,items[0].snapshot.modificationDate)
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)")
    }
    func testCopyLockedFolderUndo() async throws {
        let items=try await fixtureGroup(),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let before=try FileIdentityReader().fingerprint(at:items[0].snapshot.url)
        let plan=try await productionPlan(items,finder:[.locked(true)],mode:.saveCopies),report=try await execute(plan,driver:driver)
        XCTAssertTrue(report.success,"\(report.results)");guard report.success else {return}
        let target=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.source.snapshot.kind == .directory}).name.finalURL
        let child=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.source.snapshot.kind == .regular}).name.finalURL
        XCTAssertTrue(BatchPlanner.isWithin(child,target),"The fixture must exercise a child inside its locked copy folder")
        defer {_ = chflags(target.path,0);_ = chflags(target.appendingPathComponent("child.jpg").path,0)}
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(restored.isComplete,"\(restored.conflicts)");XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:items[0].snapshot.url))
        let again=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(again.isComplete,"\(again.conflicts)")
    }
    func testCopyFolderWithExternalChildRemainsInPlace() async throws {
        let items=try await fixtureGroup(),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let plan=try await productionPlan(items,finder:[.locked(true)],mode:.saveCopies),report=try await execute(plan,driver:driver)
        XCTAssertTrue(report.success,"\(report.results)");guard report.success else {return}
        let target=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.source.snapshot.kind == .directory}).name.finalURL,extra=target.appendingPathComponent("external.txt")
        defer {_ = chflags(target.path,0);_ = chflags(target.appendingPathComponent("child.jpg").path,0)}
        XCTAssertEqual(chflags(target.path,0),0);try Data("external data".utf8).write(to:extra);XCTAssertEqual(chflags(target.path,UInt32(UF_IMMUTABLE)),0)
        let restored=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(restored.isComplete)
        XCTAssertEqual(try Data(contentsOf:extra),Data("external data".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.appendingPathComponent("child.jpg").path))
        XCTAssertTrue(try FileIdentityReader().snapshot(at:target).isLocked)
    }
}
