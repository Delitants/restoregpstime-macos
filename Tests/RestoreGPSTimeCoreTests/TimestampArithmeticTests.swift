import XCTest
@testable import RestoreGPSTimeCore
final class TimestampArithmeticTests:XCTestCase {
    func testExactPositiveNegativeAndSequenceArithmetic() throws {
        let time=try FileTimestamp(seconds:10,nanoseconds:100_000_000)
        XCTAssertEqual(try time.adding(seconds:1),try FileTimestamp(seconds:11,nanoseconds:100_000_000))
        XCTAssertEqual(try time.adding(seconds:-0.25),try FileTimestamp(seconds:9,nanoseconds:850_000_000))
        XCTAssertEqual(try time.adding(seconds:0.1,multiplier:3),try FileTimestamp(seconds:10,nanoseconds:400_000_000))
        XCTAssertEqual(try time.adding(seconds:0.000000001),try FileTimestamp(seconds:10,nanoseconds:100_000_001))
        XCTAssertEqual(try FileTimestamp(seconds:-1,nanoseconds:999_999_999).adding(seconds:0.000000001),try FileTimestamp(seconds:0,nanoseconds:0))
        XCTAssertEqual(try FileTimestamp(seconds:1,nanoseconds:123_456_780).fractionalPrecision,8)
        XCTAssertEqual(time.fractionalPrecision,1)
        XCTAssertEqual(try FileTimestamp(seconds:-1,nanoseconds:900_000_000).adding(seconds:-0.2),try FileTimestamp(seconds:-1,nanoseconds:700_000_000))
    }
    func testUnrepresentableIntervalsAndOverflowReject() throws {
        let time=try FileTimestamp(seconds:0,nanoseconds:0)
        for value in [Double.infinity,Double.nan,0.0000000001,1e300] {XCTAssertThrowsError(try time.adding(seconds:value))}
        XCTAssertThrowsError(try FileTimestamp(seconds:Int64.max,nanoseconds:0).adding(seconds:1))
        XCTAssertThrowsError(try FileTimestamp(seconds:Int64.min,nanoseconds:0).adding(seconds:-1))
        XCTAssertThrowsError(try time.adding(seconds:1e9,multiplier:Int.max))
    }
    func testMalformedRawNanosecondsRejectOnDecode() throws {
        for value in [-1,1_000_000_000] {XCTAssertThrowsError(try JSONDecoder().decode(FileTimestamp.self,from:Data("{\"seconds\":0,\"nanoseconds\":\(value)}".utf8)))}
    }
}
