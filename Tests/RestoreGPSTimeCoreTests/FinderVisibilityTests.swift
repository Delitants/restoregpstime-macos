import XCTest
@testable import RestoreGPSTimeCore

final class FakeFinderVisibilityBackend:FinderVisibilityBackend,@unchecked Sendable {
    private let lock=NSLock()
    private var value:FinderPreferenceValue
    private var writeCounter=0,restartCounter=0
    var restartAllowed=true
    let unrelated=["UnrelatedPreference":"must stay unchanged"]
    init(_ value:FinderPreferenceValue = .absent) {self.value=value}
    func read() throws -> FinderPreferenceValue {lock.lock();defer {lock.unlock()};return value}
    func write(_ value:FinderPreferenceValue) throws {lock.lock();defer {lock.unlock()};self.value=value;writeCounter+=1}
    func external(_ value:FinderPreferenceValue) {lock.lock();self.value=value;lock.unlock()}
    func restart() async -> Bool {recordRestart()}
    private func recordRestart()->Bool {lock.lock();defer {lock.unlock()};restartCounter+=1;return restartAllowed}
    var counts:(Int,Int) {lock.lock();defer {lock.unlock()};return (writeCounter,restartCounter)}
}
final class FinderVisibilityTests:CoreTestCase {
    func testCancelledVisibilityDoesNothing() async throws {
        let backend=FakeFinderVisibilityBackend(),controller=FinderVisibilityController(backend:backend)
        _ = try await controller.preview(visible:true)
        XCTAssertEqual(try backend.read(),.absent);XCTAssertEqual(backend.counts.0,0);XCTAssertEqual(backend.counts.1,0)
    }
    func testShowHideTouchOnlyOneKey() async throws {
        let backend=FakeFinderVisibilityBackend(),controller=FinderVisibilityController(backend:backend)
        let show=try await controller.preview(visible:true)
        let result=try await controller.apply(show,restartApproved:true)
        XCTAssertTrue(result.restarted);XCTAssertEqual(try backend.read(),.bool(true))
        let hide=try await controller.preview(visible:false)
        _ = try await controller.apply(hide,restartApproved:false)
        XCTAssertEqual(try backend.read(),.bool(false));XCTAssertEqual(backend.counts.0,2);XCTAssertEqual(backend.counts.1,1)
        XCTAssertEqual(backend.unrelated,["UnrelatedPreference":"must stay unchanged"])
    }
    func testRestoreAbsentKeyAndExactLegacyState() async throws {
        for initial in [FinderPreferenceValue.absent,.bool(false),.string("TRUE"),.integer(1)] {
            let backend=FakeFinderVisibilityBackend(initial),controller=FinderVisibilityController(backend:backend)
            let change=try await controller.preview(visible:true)
            _ = try await controller.apply(change,restartApproved:false)
            _ = try await controller.restorePrevious(restartApproved:false)
            XCTAssertEqual(try backend.read(),initial);XCTAssertEqual(backend.counts.1,0)
        }
    }
    func testExternalPreferenceConflict() async throws {
        let backend=FakeFinderVisibilityBackend(.bool(false)),controller=FinderVisibilityController(backend:backend)
        let change=try await controller.preview(visible:true);backend.external(.string("external"))
        do {_ = try await controller.apply(change,restartApproved:true);XCTFail("External state must win")} catch let error as RestoreError {XCTAssertEqual(error.code,.conflict)}
        XCTAssertEqual(backend.counts.0,0);XCTAssertEqual(backend.counts.1,0)
        backend.external(.bool(false));let fresh=try await controller.preview(visible:true)
        _ = try await controller.apply(fresh,restartApproved:false);backend.external(.bool(false))
        do {_ = try await controller.restorePrevious(restartApproved:true);XCTFail("Restore must detect an intervening preference change")} catch let error as RestoreError {XCTAssertEqual(error.code,.conflict)}
        XCTAssertEqual(backend.counts.0,1);XCTAssertEqual(backend.counts.1,0)
    }
    func testFinderRestartRefusalIsReported() async throws {
        let backend=FakeFinderVisibilityBackend();backend.restartAllowed=false
        let controller=FinderVisibilityController(backend:backend),change=try await controller.preview(visible:true)
        let result=try await controller.apply(change,restartApproved:true)
        XCTAssertFalse(result.restarted);XCTAssertTrue(result.requiresRestart);XCTAssertFalse(result.note.isEmpty)
        XCTAssertEqual(try backend.read(),.bool(true))
    }
    func testPreviousStateSurvivesControllerRecreation() async throws {
        let backend=FakeFinderVisibilityBackend(.string("NO")),folder=try FileSystemPath.canonicalDirectory(workspace).appendingPathComponent("preferences")
        try SecureFS.privateDirectory(folder)
        let record=folder.appendingPathComponent("finder-visibility.json"),controller=FinderVisibilityController(backend:backend,recordURL:record)
        let change=try await controller.preview(visible:true)
        _ = try await controller.apply(change,restartApproved:false)
        let next=FinderVisibilityController(backend:backend,recordURL:record)
        _ = try await next.restorePrevious(restartApproved:false)
        XCTAssertEqual(try backend.read(),.string("NO"))
    }
}
