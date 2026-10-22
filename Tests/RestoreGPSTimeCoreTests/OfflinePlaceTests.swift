import XCTest
@testable import RestoreGPSTimeCore

final class OfflinePlaceTests:CoreTestCase {
    func testParisOffline() async throws {
        let results=try await OfflinePlaceResolver(paths:.init(appBundle:testApp)).lookup(.init(latitude:48.8566,longitude:2.3522))
        XCTAssertEqual(results.count,3)
        XCTAssertTrue(results.contains {$0.city=="Paris" && $0.countryCode=="FR"})
        XCTAssertTrue(results.allSatisfy {$0.origin == .database && $0.distanceKM != nil && !$0.databaseIdentity.isEmpty})
    }
    func testDistanceAndLimitDefaults() async throws {
        let resolver=OfflinePlaceResolver(paths:.init(appBundle:testApp))
        let one=try await resolver.lookup(.init(latitude:48.8566,longitude:2.3522,maxDistanceKM:25,limit:1))
        XCTAssertEqual(one.count,1)
        let none=try await resolver.lookup(.init(latitude:48.8566,longitude:2.3522,maxDistanceKM:0.001))
        XCTAssertTrue(none.isEmpty)
    }
    func testMissingAndConflictingGPS() async throws {
        let resolver=OfflinePlaceResolver(paths:.init(appBundle:testApp))
        do { _=try await resolver.resolve(document:.init(tags:["XMP-photoshop:City":.string("Paris")]),correction:nil);XCTFail("A city string cannot replace missing GPS") }
        catch let error as RestoreError { XCTAssertEqual(error.code,.missingMetadata) }
        let inconsistent=MetadataDocument(tags:["GPS:GPSLatitude":.real(48.8566),"GPS:GPSLatitudeRef":.string("N"),"GPS:GPSLongitude":.real(2.3522),"GPS:GPSLongitudeRef":.string("E"),"XMP-exif:GPSLatitude":.real(-33.9),"XMP-exif:GPSLongitude":.real(151.2)])
        do { _=try await resolver.resolve(document:inconsistent,correction:nil);XCTFail("Contradictory GPS must block") }
        catch let error as RestoreError { XCTAssertEqual(error.code,.conflict) }
    }
    func testZeroCoordinatesAreValidButNoNearbyMatch() async throws {
        let resolver=OfflinePlaceResolver(paths:.init(appBundle:testApp))
        let results=try await resolver.lookup(.init(latitude:0,longitude:0))
        XCTAssertTrue(results.isEmpty)
        do { _=try await resolver.lookup(.init(latitude:.nan,longitude:2));XCTFail("Nonfinite GPS must block") }
        catch let error as RestoreError { XCTAssertEqual(error.code,.invalidInput) }
    }
    func testBorderCandidatesStayApproximate() async throws {
        let matches=try await OfflinePlaceResolver(paths:.init(appBundle:testApp)).lookup(.init(latitude:49.48,longitude:6.37,maxDistanceKM:25,limit:4))
        XCTAssertGreaterThan(Set(matches.map(\.countryCode)).count,1)
        XCTAssertTrue(matches.allSatisfy {$0.origin == .database && $0.distanceKM != nil})
    }
    func testCorrectionProvenance() async throws {
        let matches=try await OfflinePlaceResolver(paths:.init(appBundle:testApp)).resolve(document:.init(tags:[:]),correction:.init(city:"Paris",country:"France",countryCode:"FR"))
        XCTAssertEqual(matches.first?.origin,.manual)
        XCTAssertEqual(matches.first?.displayName,"Paris, France")
        XCTAssertNil(matches.first?.distanceKM)
    }
    func testGeneratedPhotoAndMovieGPS() async throws {
        let reader=MetadataReader(paths:.init(appBundle:testApp))
        let resolver=OfflinePlaceResolver(paths:.init(appBundle:testApp))
        for name in ["paris.jpg","paris.heic","paris.mov"] {
            let document=try await reader.read(snapshot:FileIdentityReader().snapshot(at:fixture(name)))
            let matches=try await resolver.resolve(document:document,correction:nil)
            XCTAssertTrue(matches.contains {$0.city=="Paris" && $0.countryCode=="FR"},name)
        }
    }
    func testMissingDatabaseIsExplicit() async throws {
        let resolver=OfflinePlaceResolver(paths:.init(appBundle:workspace.appendingPathComponent("missing.app")))
        do { _=try await resolver.lookup(.init(latitude:48.8566,longitude:2.3522));XCTFail("No online fallback is permitted") }
        catch let error as RestoreError { XCTAssertEqual(error.code,.runtimeUnavailable) }
    }
}
