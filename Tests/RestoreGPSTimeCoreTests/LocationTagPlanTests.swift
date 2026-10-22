import XCTest
@testable import RestoreGPSTimeCore

final class LocationTagPlanTests:CoreTestCase {
    let match=PlaceMatch(city:"Paris",country:"France",countryCode:"FR")
    func testAppendOncePreservesExistingComment() throws {
        let document=MetadataDocument(tags:["ExifIFD:UserComment":.string("Keep me\nParis, France")],profile:.init(identifier:"JPEG",family:.photo))
        let mutations=try LocationTagPlanner().plan(match:match,document:document,options:.init())
        XCTAssertEqual(mutations,[.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("Keep me\nParis, France"))])
    }
    func testPhotoAndVideoUseQualifiedDestinations() throws {
        let photo=try LocationTagPlanner().plan(match:match,document:.init(tags:[:],profile:.init(identifier:"HEIC",family:.photo)),options:.init())
        XCTAssertEqual(photo.first,.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("Paris, France")))
        let movie=try LocationTagPlanner().plan(match:match,document:.init(tags:[:],profile:.init(identifier:"MOV",family:.video)),options:.init())
        XCTAssertEqual(movie.first,.set(TagID(rawValue:"Keys:Description-und")!,.string("Paris, France")))
    }
    func testStructuredFieldsAndExplicitReplace() throws {
        var options=LocationWriteOptions();options.writeStructuredFields=true;options.mode = .replace
        let changes=try LocationTagPlanner().plan(match:match,document:.init(tags:["ExifIFD:UserComment":.string("old")],profile:.init(identifier:"JPEG",family:.photo)),options:options)
        XCTAssertTrue(changes.contains(.set(TagID(rawValue:"XMP-photoshop:City")!,.string("Paris"))))
        XCTAssertTrue(changes.contains(.set(TagID(rawValue:"ExifIFD:UserComment")!,.string("Paris, France"))))
    }
}
