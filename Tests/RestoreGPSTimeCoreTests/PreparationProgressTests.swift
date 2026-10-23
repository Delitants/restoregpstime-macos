import XCTest
@testable import RestoreGPSTimeCore

actor PreparationRecorder {
    var events=[PreparationProgress]()
    func append(_ event:PreparationProgress) {events.append(event)}
}
final class PreparationProgressTests:PlanningTestCase {
    func testPreviewReportsCompletedFilesAndGroupsWithoutChangingFingerprints() async throws {
        let inputs=try (0..<7).map {try item("photo-\($0).HEIC")},recorder=PreparationRecorder()
        let before=try inputs.map {try FileIdentityReader().fingerprint(at:$0.snapshot.url)}
        let plan=try await planner().preview(items:inputs,request:OperationRequest(),options:options(),progress:{await recorder.append($0)})
        let events=await recorder.events
        for stage in [PreparationProgress.Stage.fingerprinting,.planning] {
            let values=events.filter {$0.stage==stage}
            XCTAssertEqual(values.first?.completed,0);XCTAssertEqual(values.last?.completed,7)
            XCTAssertTrue(values.allSatisfy {$0.total==7})
            XCTAssertEqual(values.map(\.completed),values.map(\.completed).sorted())
        }
        XCTAssertEqual(plan.eligibleGroups.count,7)
        XCTAssertEqual(try inputs.map {try FileIdentityReader().fingerprint(at:$0.snapshot.url)},before)
    }
    func testCancellationDuringProgressStopsPlanning() async throws {
        let inputs=try (0..<5).map {try item("photo-\($0).HEIC")}
        let work=Task {try await planner().preview(items:inputs,request:OperationRequest(),options:options(),progress:{event in
            if event.stage == .fingerprinting && event.completed==1 {withUnsafeCurrentTask {$0?.cancel()}}
        })}
        do {_ = try await work.value;XCTFail("Cancelled preview cannot return a plan")} catch {}
    }
}
