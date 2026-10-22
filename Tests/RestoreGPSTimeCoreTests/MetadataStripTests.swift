import XCTest
@testable import RestoreGPSTimeCore

final class MetadataStripTests:MetadataStageTestCase {
    func testPNGStripBlocksAndAdditionalLocationRemoval() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths),writer=ExifToolWriter(paths:paths)
        let png=try ownedStage("paris.png"),pngDocument=try await reader.read(snapshot:FileIdentityReader().snapshot(at:png))
        let original=try FileIdentityReader().fingerprint(at:png)
        do {_ = try await MetadataMutationDriver(paths:paths).apply(.init(stripMetadata:true,profile:pngDocument.profile,allowedMetadataChanges:.init(stripsDescriptive:true)),to:png);XCTFail("PNG blanket strip is not yet qualified")} catch let error as RestoreError {XCTAssertEqual(error.code,.unsupported)}
        XCTAssertEqual(original,try FileIdentityReader().fingerprint(at:png))
        for file in ["paris.tiff","geometric-baseline.webp","geometric-baseline.avif","geometric-baseline.mp4"] {
            do {
            let stage=try ownedStage(file),document=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            if document.profile.family == .video {
                try await writer.run(["-overwrite_original_in_place","-P","-Keys:GPSCoordinates=+48.8566+002.3522/"],to:stage)
            } else {
                _ = try await writer.write([.set(TagID(rawValue:"XMP-exif:GPSLatitude")!,.real(48.8566)),.set(TagID(rawValue:"XMP-exif:GPSLongitude")!,.real(2.3522))],to:stage,profile:document.profile)
            }
            let before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            XCTAssertTrue(before.tags.keys.contains {MetadataStripProfiles.looksLikeLocation($0)})
            _ = try await MetadataMutationDriver(paths:paths).apply(.init(removeGPS:true,profile:before.profile,allowedMetadataChanges:.init(removesGPS:true)),to:stage)
            let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            XCTAssertFalse(after.tags.keys.contains {MetadataStripProfiles.looksLikeLocation($0)},file)
            } catch {print("Location fixture failure: \(file): \(String(reflecting:error))");throw error}
        }
    }
    func testLocationRemovalCoverage() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),reader=MetadataReader(paths:paths)
        for file in ["paris.jpg","paris.heic","paris.png","paris.mov"] {
            let stage=try ownedStage(file),before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            XCTAssertTrue(before.tags.keys.contains {MetadataStripProfiles.looksLikeLocation($0)})
            let mutation=MutationPlan(removeGPS:true,profile:before.profile,allowedMetadataChanges:.init(removesGPS:true))
            _ = try await MetadataMutationDriver(paths:paths).apply(mutation,to:stage)
            let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            XCTAssertFalse(after.tags.keys.contains {MetadataStripProfiles.looksLikeLocation($0)},file)
            XCTAssertEqual(before.tags["ExifIFD:DateTimeOriginal"],after.tags["ExifIFD:DateTimeOriginal"])
            XCTAssertEqual(before.tags["Keys:CreationDate"],after.tags["Keys:CreationDate"])
        }
    }
    func testStripPreservesRenderingAndIdentifiers() async throws {
        let paths=try RuntimeLocator().locate(in:testApp),stage=try ownedStage("paris.jpg"),writer=ExifToolWriter(paths:paths),reader=MetadataReader(paths:paths)
        try await writer.run(["-overwrite_original_in_place","-P","-n","-IFD0:Orientation=6","-XMP-xmpMM:DocumentID=urn:uuid:generated-link-1"],to:stage)
        let before=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage)),signature=try await MediaIntegrityValidator().signature(at:stage,profile:before.profile)
        try JSONEncoder().encode(before).write(to:stage.deletingLastPathComponent().appendingPathComponent("strip-before.json"))
        try JSONEncoder().encode(signature).write(to:stage.deletingLastPathComponent().appendingPathComponent("signature-before.json"))
        try FileManager.default.copyItem(at:stage,to:stage.deletingLastPathComponent().appendingPathComponent("strip-before.jpg"))
        do {_ = try await MetadataMutationDriver(paths:paths).apply(.init(stripMetadata:true,profile:before.profile,allowedMetadataChanges:.init(stripsDescriptive:true)),to:stage)}
        catch {
            let diagnostics=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage))
            try JSONEncoder().encode(diagnostics).write(to:stage.deletingLastPathComponent().appendingPathComponent("strip-after.json"))
            let actual=try await MediaIntegrityValidator().signature(at:stage,profile:before.profile)
            try JSONEncoder().encode(actual).write(to:stage.deletingLastPathComponent().appendingPathComponent("signature-after.json"))
            throw error
        }
        let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage)),newSignature=try await MediaIntegrityValidator().signature(at:stage,profile:before.profile)
        XCTAssertEqual(signature,newSignature)
        XCTAssertEqual(after.tags["IFD0:Orientation"],before.tags["IFD0:Orientation"])
        XCTAssertEqual(after.tags["XMP-xmpMM:DocumentID"],before.tags["XMP-xmpMM:DocumentID"])
        XCTAssertNil(after.tags["ExifIFD:DateTimeOriginal"])
        try MetadataStripProfiles().verifyLocationRemoved(in:after)
    }

    func testRAWStripBlocks() throws {
        for format in ["CR2","CR3","NEF","ARW","DNG","HEIC","MOV"] {XCTAssertThrowsError(try MetadataStripProfiles().validateStrip(profile:.init(identifier:format,family:.raw)))}
    }
    func testLocationTrackRemainderIsNotSuccess() throws {
        let document=MetadataDocument(tags:["GoPro:GPSLatitude":.array([.real(48.8)])],profile:.init(identifier:"MOV",family:.video))
        XCTAssertThrowsError(try MetadataStripProfiles().locationRemovals(in:document))
    }
}
