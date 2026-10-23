import XCTest
@testable import RestoreGPSTimeCore

final class MetadataBatchTests:CoreTestCase {
    func testBatchDecodingMatchesEachDocumentToItsExactSource() throws {
        let urls=[workspace.appendingPathComponent("-a\n$.jpg"),workspace.appendingPathComponent("é b.heic")]
        let records:[[String:Any]]=[
            ["SourceFile":urls[0].path,"File:FileType":"JPEG","ExifIFD:DateTimeOriginal":"2024:01:02 03:04:05"],
            ["SourceFile":urls[1].path,"File:FileType":"HEIC","ExifTool:Warning":"Retained warning"]]
        let data=try JSONSerialization.data(withJSONObject:records)
        let docs=try MetadataDecoder().decodeBatch(data,expectedURLs:urls)
        XCTAssertEqual(docs.count,2);XCTAssertEqual(docs[0],try MetadataDecoder().decode(JSONSerialization.data(withJSONObject:[records[0]])))
        XCTAssertEqual(docs[1].diagnostics,["Retained warning"])
        XCTAssertThrowsError(try MetadataDecoder().decodeBatch(data,expectedURLs:urls.reversed()))
        XCTAssertThrowsError(try MetadataDecoder().decodeBatch(data,expectedURLs:[urls[0]]))
        XCTAssertThrowsError(try MetadataDecoder().decodeBatch(data,expectedURLs:[urls[0],urls[0]]))
    }
    func testBatchedHelperRetainsPerFileErrorsAndUsesOneLaunch() async throws {
        let good=workspace.appendingPathComponent("-good\n$.heic"),bad=workspace.appendingPathComponent("bad.jpg")
        try FileManager.default.copyItem(at:fixture("paris.heic"),to:good)
        try Data().write(to:bad)
        let snapshots=try [good,bad].map {try FileIdentityReader().snapshot(at:$0)}
        let before=try snapshots.map {try FileIdentityReader().fingerprint(at:$0.url)}
        let reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        let documents=try await reader.readBatch(snapshots:snapshots)
        XCTAssertEqual(documents.count,2);XCTAssertEqual(documents[0].profile.identifier,"HEIC")
        XCTAssertFalse(documents[1].diagnostics.isEmpty)
        let metrics=await reader.metrics();XCTAssertEqual(metrics.helperLaunches,1);XCTAssertEqual(metrics.completed,2)
        XCTAssertEqual(try snapshots.map {try FileIdentityReader().fingerprint(at:$0.url)},before)
    }
    func testBatchSizeIsBoundedAndCancelledReadsDoNotLaunch() async throws {
        let snapshot=try FileIdentityReader().snapshot(at:fixture("paris.jpg")),reader=MetadataReader(paths:RuntimePaths(appBundle:testApp))
        do {_ = try await reader.readBatch(snapshots:Array(repeating:snapshot,count:33));XCTFail("Oversized batch must fail")} catch {}
        let work=Task {withUnsafeCurrentTask {$0?.cancel()};return try await reader.readBatch(snapshots:[snapshot])}
        do {_ = try await work.value;XCTFail("Cancelled read must fail")} catch {}
        let metrics=await reader.metrics();XCTAssertEqual(metrics.helperLaunches,0)
    }
}
