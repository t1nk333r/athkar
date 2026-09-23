@testable import AthkarCore
import Foundation
import Testing

struct StorageInstantTests {
    @Test(arguments: [
        "2026-09-22T17:38:40.481Z",
        "2024-02-29T00:00:00.000Z",
        "1969-12-31T23:59:59.999Z",
        "2000-03-01T12:00:00.001Z",
    ])
    func toISOStringInstantsRoundTripExactly(text: String) throws {
        let date = try #require(ISOInstant.parse(text))
        #expect(date == Instant.at(text))
        #expect(ISOInstant.format(date) == text)
    }

    @Test func otherFractionLengthsAreReadAndWrittenAsMilliseconds() {
        #expect(ISOInstant.parse("2026-09-21T05:10:00Z").map(ISOInstant.format) == "2026-09-21T05:10:00.000Z")
        #expect(ISOInstant.parse("2026-09-21T05:10:00.5Z").map(ISOInstant.format) == "2026-09-21T05:10:00.500Z")
        #expect(ISOInstant.parse("2026-09-21T05:10:00.123456Z").map(ISOInstant.format) == "2026-09-21T05:10:00.123Z")
    }

    /// JS `toISOString()` truncates to whole milliseconds; rounding would print `.482` and `.000` of the next second.
    /// Built from integer nanoseconds half a millisecond past a whole one, so the two are distinguishable.
    @Test(arguments: [(481_500_000, "2026-09-22T17:38:40.481Z"), (999_500_000, "2026-09-22T17:38:40.999Z"),
                      (500_000, "2026-09-22T17:38:40.000Z")])
    func formattingTruncatesToMillisecondsLikeJavaScript(nanoseconds: Int, expected: String) {
        let seconds = 1_790_098_720 // 2026-09-22T17:38:40Z
        let date = Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
        #expect(ISOInstant.format(date) == expected)
    }

    @Test(arguments: [
        "2026-02-29T00:00:00.000Z", "2026-02-30T00:00:00.000Z", "2026-13-01T00:00:00.000Z",
        "2026-09-22T24:00:00.000Z", "2026-09-22T23:60:00.000Z", "2026-09-22T23:59:60.000Z",
        "2026-09-22T17:38:40.481z", "2026-09-22T17:38:40.481", "2026-09-22T17:38:40.Z",
        "2026-09-22 17:38:40.481Z", "2026-09-22T17:38:40.481+03:00", "",
    ])
    func rejectsInstantsThatAreNotRealUTCTimes(text: String) {
        #expect(ISOInstant.parse(text) == nil)
    }

    @Test func localDatesMustBeRealCalendarDays() {
        #expect(LocalDate.isValid("2024-02-29"))
        #expect(LocalDate.isValid("2026-12-31"))
        #expect(!LocalDate.isValid("2026-02-29"))
        #expect(!LocalDate.isValid("1900-02-29"))
        #expect(!LocalDate.isValid("2026-04-31"))
        #expect(!LocalDate.isValid("2026-9-22"))
        #expect(!LocalDate.isValid("2026-09-22T"))
    }
}
