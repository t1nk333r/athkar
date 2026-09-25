import AthkarCore
import Foundation
import Testing

struct SessionCalendarTests {
    /// `localDateKey` uses the zone's offset at the instant itself: the last and first millisecond of local days
    /// in standard time, summer time, and on both DST change days. Any single fixed offset misdates one of them.
    @Test(arguments: [
        ("2026-01-16T07:59:59.999Z", "2026-01-15"), ("2026-01-16T08:00:00.000Z", "2026-01-16"),
        ("2026-07-16T06:59:59.999Z", "2026-07-15"), ("2026-07-16T07:00:00.000Z", "2026-07-16"),
        ("2026-03-08T07:59:59.999Z", "2026-03-07"), ("2026-03-09T06:59:59.999Z", "2026-03-08"),
        ("2026-11-01T06:59:59.999Z", "2026-10-31"), ("2026-11-02T07:59:59.999Z", "2026-11-01"),
    ])
    func localDateUsesTheOffsetAtTheInstant(instant: String, expected: String) throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = Instant.at(instant)
        #expect(SessionCalendar.localDate(of: date, in: zone) == expected)
        #expect(SessionCalendar.recentDates(1, endingAt: date, in: zone) == [expected])
    }
}
