import XCTest
import Darwin
import CryptoKit
@testable import RestoreGPSTimeCore

final class LargeBatchTests:PlanningTestCase {
    func testTenThousandEntriesCancelResponsively() async throws {
        let start=Date()
        var items=[InspectedItem]();items.reserveCapacity(10000)
        for i in 0..<10000 {items.append(try item(String(format:"input/%05d.HEIC",i)))}
        let groups=try AssetGrouper().group(items:items),destination=try destination()
        let first=try NameAllocator().reserve(groups:groups,destinations:destination)
        let reversed=try NameAllocator().reserve(groups:groups.reversed(),destinations:destination)
        XCTAssertEqual(first.count,10000);XCTAssertEqual(first,reversed)
        XCTAssertEqual(Set(first.map {$0.finalURL.path}).count,10000)
        let options=try options(),planner=planner();var request=OperationRequest();request.rename=NameTemplate()
        let task=Task {try await planner.preview(items:items,request:request,options:options)}
        let cancelled=Date();task.cancel()
        do {_ = try await task.value;XCTFail("Cancelled planning cannot return an applicable plan")} catch {XCTAssertTrue(error is CancellationError || (error as? RestoreError)?.code == .cancelled)}
        XCTAssertLessThan(Date().timeIntervalSince(cancelled),2)
        print("10,000-entry generated naming + cancellation: \(Date().timeIntervalSince(start)) seconds; this is not an Instruments UI trace.")
    }
    func testLargeFilesAreStreamed() async throws {
        let url=workspace.appendingPathComponent("sparse-over-4GiB.bin"),size:UInt64=4_294_967_296+1_048_577
        let fd=open(url.path,O_CREAT|O_EXCL|O_RDWR,0o600);guard fd>=0 else {throw SecureFS.error("Create sparse fixture")};defer {close(fd)}
        guard ftruncate(fd,off_t(size))==0 else {throw SecureFS.error("Extend sparse fixture")}
        let reader=try BoundedMediaReader(url);XCTAssertEqual(reader.size,size)
        XCTAssertThrowsError(try reader.bytes(0,1_048_577));XCTAssertEqual(try reader.bytes(size-1,1),Data([0]))
        let zero=Data(repeating:0,count:1_048_576);var expected=SHA256(),remaining=size
        while remaining>0 {let n=Int(min(remaining,UInt64(zero.count)));expected.update(data:zero.prefix(n));remaining-=UInt64(n)}
        let actual=try await Task.detached {try FileIdentityReader().fingerprint(at:url)}.value
        XCTAssertEqual(actual.snapshot.id.size,size);XCTAssertEqual(actual.contentHash,expected.finalize().hex)
        let task=Task.detached {try FileIdentityReader().fingerprint(at:url)};let start=Date();task.cancel()
        do {_ = try await task.value;XCTFail("Large-file fingerprint must cancel")} catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertLessThan(Date().timeIntervalSince(start),2)
    }
    func testHelperAdmissionNeverExceedsTwo() async {
        let limiter=HelperLimiter(limit:2),counter=ConcurrencyCounter()
        await withTaskGroup(of:Void.self) {group in for _ in 0..<80 {group.addTask {await limiter.acquire();await counter.enter();try? await Task.sleep(nanoseconds:1_000_000);await counter.leave();await limiter.release()}}}
        let peak=await counter.peak;XCTAssertEqual(peak,2)
    }
}
private actor ConcurrencyCounter {var current=0,peak=0;func enter() {current+=1;peak=max(peak,current)};func leave() {current-=1}}
