import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAWireCodecTests: XCTestCase {
    func testPlainDecimalValuesRoundTripExactly() throws {
        for text in [
            "0", "1", "-12", "0.01", "1320.25", "-0.0001",
            "0.12345678901234567890123456789012345678",
            String(repeating: "9", count: 38),
            "1" + String(repeating: "0", count: 127),
            "0." + String(repeating: "0", count: 127) + "1",
        ] {
            let value = try ATADecimalCodec.decode(text)
            XCTAssertEqual(try ATADecimalCodec.encode(value), text)
            XCTAssertEqual(try ATADecimalCodec.decode(ATADecimalCodec.encode(value)), value)
        }
    }

    func testNormalizationMatchesBackendWhitespaceAndTrailingZeroSemantics() throws {
        for (input, expected) in [
            (" \t12.500\n", "12.5"), ("-0.00", "0"),
            ("1.0" + String(repeating: "0", count: 100), "1"),
        ] {
            XCTAssertEqual(try ATADecimalCodec.encode(ATADecimalCodec.decode(input)), expected)
        }
    }

    func testMalformedDecimalsAreRejectedCompletely() {
        for text in [
            "", " ", "123junk", "junk123", "1,000", "1,5", "NaN", "Infinity",
            "-Infinity", "1e2", "+1", "01", "00.1", ".5", "1.", "1 2", "1\n2",
        ] {
            XCTAssertThrowsError(try ATADecimalCodec.decode(text), text) {
                XCTAssertEqual($0 as? ATAWireError, .invalidDecimal)
            }
        }
    }

    func testPrecisionLossIsRejectedInsteadOfRounded() {
        let text = "0.1234567890123456789012345678901234567890123456789"
        XCTAssertThrowsError(try ATADecimalCodec.decode(text)) {
            XCTAssertEqual($0 as? ATAWireError, .unrepresentableDecimal)
        }
    }

    func testUnsupportedRangeIsRejected() {
        for text in [
            String(repeating: "9", count: 200),
            "0." + String(repeating: "0", count: 200) + "1",
        ] {
            XCTAssertThrowsError(try ATADecimalCodec.decode(text)) {
                XCTAssertEqual($0 as? ATAWireError, .unrepresentableDecimal)
            }
        }
    }

    func testNaNCannotBeEncoded() {
        XCTAssertThrowsError(try ATADecimalCodec.encode(.nan))
    }

    func testFinancialCodecDoesNotEncodeJSONNumbers() throws {
        let text = try ATADecimalCodec.encode(Decimal(1320))
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(text), as: UTF8.self), "\"1320\"")
    }

    func testSixFractionalDigitsPreserveMicroseconds() throws {
        let whole = try ATATimestampCodec.decode("2026-09-25T12:00:03Z")
        let fractional = try ATATimestampCodec.decode("2026-09-25T12:00:03.123456Z")
        XCTAssertEqual(fractional.timeIntervalSince(whole), 0.123456, accuracy: 0.000001)
        XCTAssertEqual(try ATATimestampCodec.decode("2026-09-25T12:00:03.000000Z"), whole)
    }

    func testWholeSecondFallbackIsExplicit() throws {
        XCTAssertEqual(
            try ATATimestampCodec.decode("1970-01-01T00:00:00Z"), Date(timeIntervalSince1970: 0))
        XCTAssertNoThrow(try ATATimestampCodec.decode("2024-02-29T12:00:00.000000Z"))
    }

    func testInvalidCalendarDatesAndTimesAreRejected() {
        for text in [
            "2026-02-29T12:00:00.000000Z", "2026-04-31T12:00:00.000000Z",
            "2026-13-01T12:00:00.000000Z", "2026-01-01T24:00:00.000000Z",
            "2026-01-01T12:00:60.000000Z", "0000-01-01T12:00:00.000000Z",
        ] {
            XCTAssertThrowsError(try ATATimestampCodec.decode(text), text)
        }
    }

    func testOnlyFrozenUTCFormatAndWholeSecondFallbackAreAccepted() {
        for text in [
            "2026-09-25T12:00:03", "2026-09-25T12:00:03.123Z",
            "2026-09-25T12:00:03.1234567Z", "2026-09-25T12:00:03+00:00",
            "2026-09-25T12:00:03.000000+03:00", "2026-09-25T12:00:03Zjunk",
            " 2026-09-25T12:00:03Z",
        ] {
            XCTAssertThrowsError(try ATATimestampCodec.decode(text), text)
        }
    }

    func testCodecsHaveNoSharedMutableState() async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    let date = try ATATimestampCodec.decode("2026-09-25T12:00:03.123456Z")
                    let value = try ATADecimalCodec.decode(
                        "0.12345678901234567890123456789012345678")
                    let encoded = try ATADecimalCodec.encode(value)
                    return date > Date(timeIntervalSince1970: 0)
                        && encoded == "0.12345678901234567890123456789012345678"
                }
            }
            for try await valid in group { XCTAssertTrue(valid) }
        }
    }
}
