import XCTest
@testable import RestoreGPSTime

final class DisplayDateTests:XCTestCase {
    func testEveryHourIsUnambiguousInTwelveAndTwentyFourHourLocales() {
        let zone=TimeZone(secondsFromGMT:0)!
        for language in ["en_US","en_GB","fr_FR"] {
            let values=(0..<24).map {displayDate(Date(timeIntervalSince1970:Double($0*3600+245)),locale:Locale(identifier:language),timeZone:zone)}
            XCTAssertEqual(Set(values).count,24,"Every hour needs a distinct visible label in "+language)
        }
    }
    func testNilAndOffsetRemainVisible() {
        XCTAssertEqual(displayDate(nil),"—")
        let value=displayDate(Date(timeIntervalSince1970:245),locale:Locale(identifier:"en_US"),timeZone:TimeZone(secondsFromGMT:-36000)!)
        XCTAssertTrue(value.contains("-1000"));XCTAssertTrue(value.contains("05"))
    }
}
