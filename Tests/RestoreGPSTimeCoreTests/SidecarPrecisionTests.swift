import XCTest
@testable import RestoreGPSTimeCore
final class SidecarPrecisionTests:MetadataStageTestCase {
    func testSidecarSplitRetainsExactFileDatesAndCaptureFraction() async throws {
        let stage=try ownedStage("paris.jpg"),paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths),writer=ExifToolWriter(paths:paths)
        let initial=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
        _=try await writer.write([.set(TagID(rawValue:"ExifIFD:DateTimeOriginal")!,.string("2024:01:02 03:04:05")),.set(TagID(rawValue:"ExifIFD:OffsetTimeOriginal")!,.string("+02:00")),.set(TagID(rawValue:"ExifIFD:SubSecTimeOriginal")!,.string("123456789"))],to:stage,profile:initial.profile)
        let before=try FileIdentityReader().fingerprint(at:stage),document=try await reader.read(snapshot:before.snapshot),input=InspectedItem(snapshot:before.snapshot,metadata:document)
        let identity=DependencyIdentity(engineHash:"test",databaseHash:"test",capabilityHash:"test")
        var request=OperationRequest();var policy=DatePolicy();policy.targets=[.creation,.modification,.capture];policy.shiftSeconds=3600;request.dates=policy;request.metadataDestination = .xmpSidecar
        var options=BatchOptions();options.outputRoot=workspace.appendingPathComponent("Output");options.recoveryRoot=workspace.appendingPathComponent("Recovery");options.importRoots=[stage]
        let plan=try await BatchPlanner(dependencies:identity,reader:reader).preview(items:[input],request:request,options:options)
        XCTAssertEqual(plan.groups.first?.eligibility,.eligible,plan.groups.flatMap(\.blockingReasons).joined(separator:"\n"))
        let expected=try FileTimestamp(seconds:Int64(try utc("2024-01-02T02:04:05Z").timeIntervalSince1970),nanoseconds:123_456_789)
        let photo=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.mutation.outputKind == .sourceCopy}),sidecar=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.mutation.outputKind == .xmpSidecar})
        XCTAssertEqual(photo.mutation.dates?.creationTimestamp,expected);XCTAssertEqual(sidecar.mutation.dates?.embeddedTimestamp,expected)
        let executor=BatchExecutor(driver:AttributeMutationDriver(paths:paths),validator:.init(dependencies:{identity}))
        var report:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let value)=event {report=value}}
        let result=try XCTUnwrap(report);XCTAssertTrue(result.success,result.results.flatMap(\.errors).joined(separator:"\n"))
        let copied=try FileIdentityReader().snapshot(at:photo.name.finalURL),written=try await reader.read(snapshot:FileIdentityReader().snapshot(at:sidecar.name.finalURL))
        XCTAssertEqual(copied.creationTimestamp,expected);XCTAssertEqual(copied.modificationTimestamp,expected)
        XCTAssertTrue(written.tags["XMP-exif:DateTimeOriginal"]?.text.contains(".123456789")==true)
        XCTAssertEqual(try FileIdentityReader().fingerprint(at:stage),before)
    }
    func testEarlierDateOnlySnapshotStillDecodesAndMatchesItsRecordedPrecision() throws {
        let current=try FileIdentityReader().fingerprint(at:ownedStage("paris.jpg")),encoder=JSONEncoder()
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(current.snapshot)) as? [String:Any]),id=try XCTUnwrap(object["id"] as? [String:Any])
        object.removeValue(forKey:"creationTimestamp");object.removeValue(forKey:"modificationTimestamp");id.removeValue(forKey:"modifiedTimestamp");id.removeValue(forKey:"changedTimestamp");object["id"]=id
        let earlier=try JSONDecoder().decode(FileSnapshot.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(earlier.creationTimestamp);XCTAssertNil(earlier.id.changedTimestamp)
        XCTAssertTrue(SecureFS.matches(current,.init(snapshot:earlier,contentHash:current.contentHash)))
    }
}
