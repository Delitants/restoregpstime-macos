import XCTest
@testable import RestoreGPSTimeCore

// Deliberately synthetic item graph. Tests parser invariants, never camera/depth qualification.
final class HEIFGraphTests:CoreTestCase {
    func testAuxiliaryPayloadAndRelationshipsAreCovered() throws {
        let file=workspace.appendingPathComponent("synthetic.heic")
        try graph().write(to:file)
        XCTAssertThrowsError(try HEIFIntegrity().signature(BoundedMediaReader(file),profile:"HEIC"))
        let parser=HEIFIntegrity(allowQualifiedAuxiliary:true)
        let original=try parser.signature(BoundedMediaReader(file),profile:"HEIC")
        try graph(auxiliaryPayload:Data([1,2,3,9])).write(to:file)
        let alteredPayload=try parser.signature(BoundedMediaReader(file),profile:"HEIC")
        XCTAssertNotEqual(original.payloadHash,alteredPayload.payloadHash)
        try graph(referenceTarget:2).write(to:file)
        let alteredRelationship=try parser.signature(BoundedMediaReader(file),profile:"HEIC")
        XCTAssertNotEqual(original.structureHash,alteredRelationship.structureHash)
        XCTAssertThrowsError(try MediaIntegrityValidator().verify(before:original,after:alteredRelationship,allowedChanges:.init()))
    }
    func testChromaHighBitDepthNeedsQualification() throws {
        let file=workspace.appendingPathComponent("high-chroma.heic")
        try graph(auxiliary:false,chromaDepth:2).write(to:file)
        XCTAssertThrowsError(try HEIFIntegrity().signature(BoundedMediaReader(file),profile:"HEIC"))
    }
    private func graph(auxiliary:Bool=true,chromaDepth:UInt8=0,auxiliaryPayload:Data=Data([1,2,3,4]),referenceTarget:UInt64=1)->Data {
        func n(_ value:UInt64,_ width:Int)->Data {Data((0..<width).reversed().map {UInt8(truncatingIfNeeded:value>>($0*8))})}
        func box(_ type:String,_ contents:Data)->Data {n(UInt64(contents.count+8),4)+Data(type.utf8)+contents}
        func full(_ version:UInt8=0)->Data {Data([version,0,0,0])}
        let ftyp=box("ftyp",Data("heic".utf8)+n(0,4)+Data("heicmif1".utf8))
        func infe(_ id:UInt64)->Data {box("infe",full(2)+n(id,2)+n(0,2)+Data("hvc1\0".utf8))}
        let info=box("iinf",full()+n(2,2)+infe(1)+infe(2)),pitm=box("pitm",full()+n(1,2))
        var codec=Data(repeating:0,count:23);codec[18]=chromaDepth
        let configuration=box("hvcC",codec),dimensions=box("ispe",full()+n(2,4)+n(2,4))
        let aux=auxiliary ? box("auxC",full()+Data("urn:mpeg:hevc:2015:auxid:1\0".utf8)):Data()
        let associations=full()+n(2,4)+n(1,2)+Data([2,0x81,0x82])+n(2,2)+(auxiliary ? Data([3,0x81,0x82,0x83]):Data([2,0x81,0x82]))
        let properties=box("iprp",box("ipco",configuration+dimensions+aux)+box("ipma",associations))
        let reference=box("iref",full()+box(auxiliary ? "auxl":"dimg",n(2,2)+n(1,2)+n(referenceTarget,2)))
        func meta(_ offset:UInt64)->Data {
            func extent(_ id:UInt64,_ at:UInt64)->Data {n(id,2)+n(0,2)+n(0,2)+n(1,2)+n(at,4)+n(4,4)}
            let locations=box("iloc",full(1)+Data([0x44,0])+n(2,2)+extent(1,offset)+extent(2,offset+4))
            return box("meta",full()+pitm+info+locations+reference+properties)
        }
        let offset=UInt64(ftyp.count+meta(0).count+8)
        return ftyp+meta(offset)+box("mdat",Data([5,6,7,8])+auxiliaryPayload)
    }
}
