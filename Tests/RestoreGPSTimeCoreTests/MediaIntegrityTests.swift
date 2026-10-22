import XCTest
@testable import RestoreGPSTimeCore

final class MediaIntegrityTests:CoreTestCase {
    func testNewXMPSidecarIsBoundedAndDoesNotLoadEntities() async throws {
        let file=workspace.appendingPathComponent("new.xmp"),profile=ContainerProfile(identifier:"XMP",family:.unknown)
        try Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\"/></rdf:RDF></x:xmpmeta>".utf8).write(to:file)
        _ = try await MediaIntegrityValidator().signature(at:file,profile:profile)
        try Data("<!DOCTYPE a [<!ENTITY secret SYSTEM \"file:///etc/hosts\">]><a>&secret;</a>".utf8).write(to:file)
        do {_ = try await MediaIntegrityValidator().signature(at:file,profile:profile);XCTFail("Entities must remain disabled")} catch is RestoreError {}
    }
    func testProtectedPayloadCorruptionRejected() async throws {
        let original=try fixture("paris.jpg"),copy=workspace.appendingPathComponent("corrupt.jpg")
        var data=try Data(contentsOf:original)
        guard let scan=data.range(of:Data([0xff,0xda])) else {return XCTFail("Generated JPEG has no scan")}
        let at=min(data.count-4,scan.lowerBound+30);data[at] ^= 0x01;try data.write(to:copy)
        let validator=MediaIntegrityValidator(),profile=ContainerProfile(identifier:"JPEG",family:.photo)
        let before=try await validator.signature(at:original,profile:profile),after=try await validator.signature(at:copy,profile:profile)
        XCTAssertNotEqual(before.payloadHash,after.payloadHash)
        XCTAssertThrowsError(try validator.verify(before:before,after:after,allowedChanges:.init()))
    }
    func testMalformedExtentsAndUnverifiedRAWBlock() async throws {
        let invalid=workspace.appendingPathComponent("broken.heic");try Data([0,0,0,255,0x6d,0x65,0x74,0x61]).write(to:invalid)
        for profile in [ContainerProfile(identifier:"HEIC",family:.photo),.init(identifier:"CR3",family:.raw)] {
            do {_ = try await MediaIntegrityValidator().signature(at:invalid,profile:profile);XCTFail("Unproved media must block")} catch is RestoreError {}
        }
    }
    func testAdditionalPhotoSignatures() async throws {
        for (url,type) in [(try fixture("geometric-baseline.webp"),"WEBP"),(try fixture("geometric-baseline.avif"),"AVIF")] {
            let result=try await MediaIntegrityValidator().signature(at:url,profile:.init(identifier:type,family:.photo))
            XCTAssertFalse(result.payloadHash.isEmpty);XCTAssertNotEqual(result.validator,"unimplemented")
        }
    }
    func testPhotoContainerSignaturesAreNonempty() async throws {
        for format in ["jpg","png","tiff"] {
            let type=["jpg":"JPEG","png":"PNG","tiff":"TIFF"][format]!
            let result=try await MediaIntegrityValidator().signature(at:fixture("paris."+format),profile:.init(identifier:type,family:.photo))
            XCTAssertFalse(result.payloadHash.isEmpty);XCTAssertFalse(result.structureHash.isEmpty)
        }
    }
    func testHEIFBaselineAndVideoSamplesPreserved() async throws {
        let validator=MediaIntegrityValidator()
        for (file,profile) in [("paris.heic",ContainerProfile(identifier:"HEIC",family:.photo)),("paris.mov",.init(identifier:"MOV",family:.video))] {
            let signature=try await validator.signature(at:fixture(file),profile:profile)
            XCTAssertFalse(signature.payloadHash.isEmpty);XCTAssertFalse(signature.structureHash.isEmpty)
            XCTAssertNotEqual(signature.validator,"unimplemented")
        }
    }
}
