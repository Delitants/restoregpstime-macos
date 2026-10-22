import XCTest
@testable import RestoreGPSTimeCore

final class NameAllocatorTests:NamingTestCase {
    func testCountryOnlyAndCityOnlyTemplatesNeedOnlySelectedPlaceFields() throws {
        for (place,pattern,expected) in [(PlaceMatch(city:"",country:"France"),"{country}-{sequence:04}.{extension}","France-0001.HEIC"),(PlaceMatch(city:"Paris",country:""),"{city}-{sequence:04}.{extension}","Paris-0001.HEIC")] {
            let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[item("input.HEIC",place:place)]),destinations:destination(),template:.init(pattern))
            XCTAssertNil(names.first?.blockingReason);XCTAssertEqual(names.first?.finalURL.lastPathComponent,expected)
        }
    }
    func testEqualLengthTruncationUsesStableFieldPriority() throws {
        let place=PlaceMatch(city:"DDDD",country:"CCCC"),input=try item("a.HEIC",place:place)
        for _ in 0..<12 {
            let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[input]),destinations:destination(rules:.init(maxNameBytes:18)),template:.init("{country}-{city}-{sequence:04}.{extension}"))
            XCTAssertEqual(names.first?.finalURL.lastPathComponent,"CCC-DDDD-0001.HEIC")
        }
    }
    func testSamePlaceIncrementsByStableOrder() throws {
        let groups=try AssetGrouper().group(items:[item("b.MOV",family:.video),item("a.HEIC")])
        let context=try destination()
        let names=try NameAllocator().reserve(groups:groups,destinations:context)
        XCTAssertEqual(names.map {$0.finalURL.lastPathComponent},["France - Paris - 0001.HEIC","France - Paris - 0002.MOV"])
        XCTAssertEqual(names,try NameAllocator().reserve(groups:groups,destinations:context))
    }
    func testCaseAndUnicodeCollision() throws {
        let rules=VolumeNamingRules(caseSensitive:false)
        XCTAssertEqual(rules.collisionKey("ÉTÉ.HEIC"),rules.collisionKey("E\u{301}te\u{301}.heic"))
        XCTAssertNotEqual(VolumeNamingRules(caseSensitive:true).collisionKey("A"),VolumeNamingRules(caseSensitive:true).collisionKey("a"))
    }
    func testExistingNameAdvancesSequence() throws {
        let context=try destination()
        try Data("unrelated".utf8).write(to:context.root!.appendingPathComponent("france - paris - 0001.heic"))
        let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[item("a.HEIC")]),destinations:context)
        XCTAssertEqual(names.first?.finalURL.lastPathComponent,"France - Paris - 0002.HEIC")
        XCTAssertEqual(try Data(contentsOf:context.root!.appendingPathComponent("france - paris - 0001.heic")),Data("unrelated".utf8))
    }
    func testCrossRootCollision() throws {
        let a=try item("first/Images/a.HEIC"),b=try item("second/Images/a.HEIC")
        let context=DestinationContext(root:try destination().root,saveCopies:true,importRoots:[a.snapshot.url.deletingLastPathComponent(),b.snapshot.url.deletingLastPathComponent()])
        let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[a,b]),destinations:context,template:.original)
        XCTAssertEqual(names.count,2);XCTAssertEqual(Set(names.map {$0.finalURL.path}).count,2)
    }
    func testInvalidComponentsAndLength() throws {
        let place=PlaceMatch(city:String(repeating:"東",count:100)+"/City:\n",country:"France")
        let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[item("a.HEIC",place:place)]),destinations:destination(rules:.init(maxNameBytes:80)))
        XCTAssertEqual(names.count,1)
        let name=try XCTUnwrap(names.first)
        XCTAssertLessThanOrEqual(name.finalURL.lastPathComponent.utf8.count,80)
        XCTAssertTrue(name.wasTruncated)
        XCTAssertTrue(name.finalURL.lastPathComponent.hasSuffix("0001.HEIC"))
        XCTAssertFalse(name.finalURL.lastPathComponent.contains(":"))
        XCTAssertThrowsError(try NameAllocator().reserve(groups:[],destinations:destination(),template:.init("../{city}/{sequence:04}.{extension}")))
    }
    func testCaseOnlyRenameAndCycles() throws {
        let original=try item("france - paris - 0001.heic")
        let context=DestinationContext(saveCopies:false,rules:.init(caseSensitive:false))
        let names=try NameAllocator().reserve(groups:AssetGrouper().group(items:[original]),destinations:context)
        XCTAssertEqual(names.count,1);XCTAssertTrue(try XCTUnwrap(names.first).needsTemporaryRename)
        let second=try item("France - Paris - 0002.heic")
        let all=try NameAllocator().reserve(groups:AssetGrouper().group(items:[original,second]),destinations:context)
        XCTAssertEqual(Set(all.map {$0.finalURL.path}).count,2)
    }
}
