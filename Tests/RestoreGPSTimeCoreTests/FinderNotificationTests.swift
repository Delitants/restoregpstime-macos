import XCTest
import Darwin
@testable import RestoreGPSTimeCore

actor RecordedFinderNotifier:FinderNotifying {
    private(set) var received=[URL]()
    func notify(changed urls:[URL]) async {received+=urls}
}
struct RejectMutationDriver:MutationDriver {
    func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification {throw RestoreError(.verificationFailed,"A pure Finder notification must not stage or replace a file")}
    func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws {throw RestoreError(.verificationFailed,"No restoration is required for a notification")}
}
final class FinderNotificationTests:TransactionTestCase {
    func testNativeFinderNotificationLeavesAttributesUnchanged() async throws {
        let input=try item("native-notice.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        await FinderNotifier().notify(changed:[input.snapshot.url])
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
    }
    func testNotificationDoesNotMutateFilesOrRequireRecovery() async throws {
        let input=try item("notify.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),notifier=RecordedFinderNotifier()
        var request=OperationRequest();request.finder=[.notify]
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=nil
        let plan=try await planner().preview(items:[input],request:request,options:settings),expected=self.identity
        let executor=BatchExecutor(driver:RejectMutationDriver(),validator:.init(dependencies:{expected}),notifier:notifier)
        var report:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let result)=event {report=result}}
        XCTAssertTrue(try XCTUnwrap(report).success)
        XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        let received=await notifier.received;XCTAssertEqual(received.map(\.path),[input.snapshot.url.path])
    }
    func testLockedAndHardlinkedFilesCanBeNotified() async throws {
        let initial=try item("locked.HEIC"),url=initial.snapshot.url
        try FileManager.default.linkItem(at:url,to:workspace.appendingPathComponent("another-name"))
        XCTAssertEqual(chflags(url.path,UInt32(UF_IMMUTABLE)),0);defer {_ = chflags(url.path,0)}
        let item=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:url),metadata:initial.metadata)
        var request=OperationRequest();request.finder=[.notify]
        let plan=try await preview(item,request:request,mode:.modifyInPlace)
        XCTAssertEqual(plan.eligibleGroups.count,1)
        let before=try FileIdentityReader().fingerprint(at:url),expected=self.identity,notifier=RecordedFinderNotifier()
        let executor=BatchExecutor(driver:RejectMutationDriver(),validator:.init(dependencies:{expected}),notifier:notifier)
        var report:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let result)=event {report=result}}
        XCTAssertTrue(try XCTUnwrap(report).success);XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:url))
    }
    func testCombinedMutationsNotifyCommittedTargets() async throws {
        let input=try item("dates.HEIC"),expected=self.identity,notifier=RecordedFinderNotifier()
        var request=OperationRequest();request.finder=[.notify];request.dates=DatePolicy();request.dates?.source = .specific(try utc("2020-02-03T04:05:06Z"));request.dates?.targets = .modification
        let plan=try await preview(input,request:request,mode:.modifyInPlace),driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp))
        let executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}),notifier:notifier)
        var report:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let result)=event {report=result}}
        let result=try XCTUnwrap(report);XCTAssertTrue(result.success,"\(result.results)")
        let received=await notifier.received;XCTAssertEqual(received,result.results.flatMap(\.outputs))
        XCTAssertEqual(try FileIdentityReader().snapshot(at:input.snapshot.url).modificationDate,try utc("2020-02-03T04:05:06Z"))
    }
}
