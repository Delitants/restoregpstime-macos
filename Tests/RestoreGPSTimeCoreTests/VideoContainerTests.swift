import XCTest
@testable import RestoreGPSTimeCore
final class VideoContainerTests:CoreTestCase {
    private func u32(_ value:UInt32)->Data {var big=value.bigEndian;return withUnsafeBytes(of:&big) {Data($0)}}
    private func box(_ type:String,_ payload:Data)->Data {u32(UInt32(payload.count+8))+Data(type.utf8)+payload}
    private func file(_ name:String,external:Bool=false,referenceMovie:Bool=false,description:String="Original handler",swapRoles:Bool=false,encrypted:Bool=false) throws -> URL {
        let media=box("hdlr",Data(repeating:0,count:4)+Data("mhlrvide".utf8)+Data(description.utf8)),data=box("hdlr",Data(repeating:0,count:4)+Data("dhlralis".utf8)+Data("Local data".utf8))
        let entry=box("url ",u32(external ? 0:1)+(external ? Data("https://example.invalid/media.mdat\0".utf8):Data()))
        let dref=box("dref",u32(0)+u32(1)+entry),dinf=box("dinf",dref)
        let sample=box(encrypted ? "encv":"avc1",Data(repeating:0,count:6)+Data([0,1]))
        let stbl=box("stbl",box("stsd",u32(0)+u32(1)+sample))
        let minf=box("minf",(swapRoles ? media:data)+dinf+stbl),mdia=box("mdia",(swapRoles ? data:media)+minf)
        let tkhd=box("tkhd",u32(0)+u32(0)+u32(0)+u32(1)+u32(0)),trak=box("trak",tkhd+mdia)
        let movie=box("moov",trak+(referenceMovie ? box("rmra",Data()):Data())),url=workspace.appendingPathComponent(name)
        try (box("ftyp",Data("qt  ".utf8)+u32(0))+movie).write(to:url)
        return url
    }
    func testSelfContainedReferencesAndProtectedHandlerRoles() throws {
        let checker=VideoContainerPreflight()
        let original=try checker.signature(at:file("base.mov")),same=try checker.signature(at:file("same.mov")),changed=try checker.signature(at:file("changed.mov",description:"Changed handler")),swapped=try checker.signature(at:file("swapped.mov",swapRoles:true))
        XCTAssertEqual(original,same);XCTAssertNotEqual(original,changed);XCTAssertNotEqual(original,swapped)
    }
    func testExternalReferenceAndReferenceMovieRejectBeforeAssetLoading() throws {
        XCTAssertThrowsError(try VideoContainerPreflight().signature(at:file("external.mov",external:true)))
        XCTAssertThrowsError(try VideoContainerPreflight().signature(at:file("reference.mov",referenceMovie:true)))
        XCTAssertThrowsError(try VideoContainerPreflight().signature(at:file("encrypted.mov",encrypted:true)))
    }
    func testGeneratedNativeMovieAndMP4HaveQualifiedReferences() throws {
        for name in ["paris.mov","geometric-baseline.mp4"] {XCTAssertEqual(try VideoContainerPreflight().signature(at:fixture(name)).count,64)}
    }
    func testMalformedContainerExtentsAndCountsReject() throws {
        let bad=workspace.appendingPathComponent("bad.mov");try (u32(UInt32.max)+Data("moov".utf8)).write(to:bad)
        XCTAssertThrowsError(try VideoContainerPreflight().signature(at:bad))
        let missing=workspace.appendingPathComponent("missing.mov");try box("moov",Data()).write(to:missing)
        XCTAssertThrowsError(try VideoContainerPreflight().signature(at:missing))
    }
}
