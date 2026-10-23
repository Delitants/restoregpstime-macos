import AppKit
import XCTest
@testable import RestoreGPSTime

final class ThumbnailProviderTests: XCTestCase {
    @MainActor func testGeneratedImageIsDownsampledCachedAndNeverModified() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("generated.png")
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:320,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let data=bitmap.representation(using:.png,properties:[:])!
        try data.write(to:url)
        let before=try FileManager.default.attributesOfItem(atPath:url.path)
        let provider=ThumbnailProvider()
        for (size,maximum) in [(ThumbnailSize.small,96.0),(.medium,192.0),(.large,320.0)] {
            let request=ThumbnailRequest(url:url,size:size,revision:"generated")
            provider.setVisible([request])
            try await waitUntil {provider.cachedResult(for:request) != nil}
            let first=try XCTUnwrap(provider.cachedResult(for:request)?.image)
            XCTAssertLessThanOrEqual(first.size.width,maximum)
            XCTAssertLessThanOrEqual(first.size.height,maximum)
            XCTAssertGreaterThan(first.size.width,maximum/2,"Do not reuse a smaller cached preview")
            provider.setVisible([])
            provider.setVisible([request])
            XCTAssertTrue(provider.cachedResult(for:request)?.image === first)
        }
        XCTAssertEqual(try Data(contentsOf:url),data)
        let after=try FileManager.default.attributesOfItem(atPath:url.path)
        XCTAssertEqual(before[.modificationDate] as? Date,after[.modificationDate] as? Date)
    }

    @MainActor func testOffDoesNotReadFilesAndUnavailableFileHasCachedPlaceholder() async throws {
        let request=ThumbnailRequest(url:URL(fileURLWithPath:"/generated/missing.png"),size:.off,revision:"")
        let probe=RenderProbe()
        let off=ThumbnailProvider(renderer:{request,_ in probe.started(request.url.path);probe.ended();return nil})
        off.setVisible([request])
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(probe.count,0)
        XCTAssertNil(off.cachedResult(for:request))
        let unavailable=ThumbnailRequest(url:request.url,size:.small,revision:"")
        let provider=ThumbnailProvider()
        provider.setVisible([unavailable])
        try await waitUntil {provider.cachedResult(for:unavailable) != nil}
        XCTAssertNil(provider.cachedResult(for:unavailable)?.image)
    }

    // Slow rendering is injected at the decode boundary so the real queue and cancellation
    // logic can be observed deterministically without timing a remote filesystem.
    @MainActor func testOnlyTwoDecodesRunAndHiddenQueuedRowsNeverDecode() async throws {
        let gate=DispatchSemaphore(value:0), probe=RenderProbe()
        let provider=ThumbnailProvider(renderer:{request,isCancelled in
            probe.started(request.url.lastPathComponent)
            gate.wait()
            probe.ended()
            return isCancelled() ? nil:NSImage(size:NSSize(width:10,height:10))
        })
        let requests=(0..<8).map {ThumbnailRequest(url:URL(fileURLWithPath:"/generated/\($0).png"),size:.small,revision:"")}
        provider.setVisible(requests)
        try await waitUntil {probe.count==2}
        provider.setVisible([])
        gate.signal();gate.signal()
        try await waitUntil {probe.active==0}
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(probe.count,2,"Hidden queued rows must not touch their files")
        XCTAssertEqual(probe.maximum,2)
        XCTAssertNil(provider.cachedResult(for:requests[0]),"Cancelled results must not be published or cached")
    }

    @MainActor func testSizeChangeRejectsOldResultAndUnsupportedFilesAreCached() async throws {
        let gate=DispatchSemaphore(value:0), probe=RenderProbe()
        let provider=ThumbnailProvider(renderer:{request,_ in
            probe.started(request.size.rawValue)
            if request.size == .small {gate.wait()}
            probe.ended()
            return nil
        })
        let url=URL(fileURLWithPath:"/generated/unsupported.bin")
        let old=ThumbnailRequest(url:url,size:.small,revision:"1")
        let current=ThumbnailRequest(url:url,size:.large,revision:"1")
        provider.setVisible([old])
        try await waitUntil {probe.count==1}
        provider.setVisible([current]);gate.signal()
        try await waitUntil {provider.cachedResult(for:current) != nil}
        XCTAssertNil(provider.cachedResult(for:old))
        XCTAssertNil(provider.cachedResult(for:current)?.image)
        provider.setVisible([]);provider.setVisible([current])
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(probe.count,2,"Unsupported thumbnails must not repeatedly decode")
        let changed=ThumbnailRequest(url:url,size:.large,revision:"2")
        provider.setVisible([changed])
        try await waitUntil {provider.cachedResult(for:changed) != nil}
        XCTAssertEqual(probe.count,3,"A new source revision must not reuse a stale result")
    }

    @MainActor private func waitUntil(_ predicate:()->Bool) async throws {
        for _ in 0..<200 {if predicate() {return};try await Task.sleep(nanoseconds:10_000_000)}
        XCTFail("Thumbnail work did not reach expected state")
    }
}

private final class RenderProbe: @unchecked Sendable {
    private let lock=NSLock()
    private var names=[String](), running=0, peak=0
    var count:Int {lock.lock();defer {lock.unlock()};return names.count}
    var active:Int {lock.lock();defer {lock.unlock()};return running}
    var maximum:Int {lock.lock();defer {lock.unlock()};return peak}
    func started(_ name:String) {lock.lock();defer {lock.unlock()};names.append(name);running+=1;peak=max(peak,running)}
    func ended() {lock.lock();defer {lock.unlock()};running-=1}
}
