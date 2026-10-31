import XCTest
@testable import AthkarModels

/// The words and countdown the home prayer row puts after «بعد».
final class ArabicFormatTests: XCTestCase {
    func testMinutesLeftUsesArabicNumberAgreement() {
        XCTAssertEqual(ArabicFormat.minutesLeft(1), "دقيقة")
        XCTAssertEqual(ArabicFormat.minutesLeft(2), "دقيقتين")
        XCTAssertEqual(ArabicFormat.minutesLeft(3), "٣ دقائق")
        XCTAssertEqual(ArabicFormat.minutesLeft(10), "١٠ دقائق")
        XCTAssertEqual(ArabicFormat.minutesLeft(11), "١١ دقيقة")
        XCTAssertEqual(ArabicFormat.minutesLeft(59), "٥٩ دقيقة")
    }

    func testMinutesLeftJoinsHoursAndMinutesWithWaw() {
        XCTAssertEqual(ArabicFormat.minutesLeft(60), "ساعة")
        XCTAssertEqual(ArabicFormat.minutesLeft(80), "ساعة و٢٠ دقيقة")
        XCTAssertEqual(ArabicFormat.minutesLeft(120), "ساعتين")
        XCTAssertEqual(ArabicFormat.minutesLeft(125), "ساعتين و٥ دقائق")
        XCTAssertEqual(ArabicFormat.minutesLeft(181), "٣ ساعات ودقيقة")
        XCTAssertEqual(ArabicFormat.minutesLeft(662), "١١ ساعة ودقيقتين")
    }

    func testCountdownIsMinutesAndTwoDigitSeconds() {
        XCTAssertEqual(ArabicFormat.countdown(seconds: 899), "١٤:٥٩")
        XCTAssertEqual(ArabicFormat.countdown(seconds: 900), "١٥:٠٠")
        XCTAssertEqual(ArabicFormat.countdown(seconds: 5), "٠:٠٥")
        XCTAssertEqual(ArabicFormat.countdown(seconds: 0), "٠:٠٠")
        XCTAssertEqual(ArabicFormat.countdown(seconds: -3), "٠:٠٠")
    }
}
