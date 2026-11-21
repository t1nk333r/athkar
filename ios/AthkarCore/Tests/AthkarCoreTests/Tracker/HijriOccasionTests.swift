import AthkarCore
import Testing

/// The calendar's Hijri dates and marked days, against the Umm al-Qura calendar: Ramadan 1447 from 2026-02-18,
/// Eid al-Fitr 2026-03-20, 'Arafah 2026-05-26, Eid al-Adha 2026-05-27, 1 Muharram 1448 2026-06-16.
struct HijriOccasionTests {
    @Test func theHijriDateIsUmmAlQuras() {
        #expect(HijriDate.of("2026-02-18", offset: 0) == HijriDate(year: 1447, month: 9, day: 1))
        #expect(HijriDate.of("2026-06-16", offset: 0) == HijriDate(year: 1448, month: 1, day: 1))
        #expect(HijriDate.of("2026-02-30", offset: 0) == nil)
    }

    /// The offset moves the date the calendar shows, and with it the marked days.
    @Test func theOffsetMovesTheDate() {
        #expect(HijriDate.of("2026-02-17", offset: 1) == HijriDate(year: 1447, month: 9, day: 1))
        #expect(HijriDate.of("2026-02-18", offset: -1) == HijriDate(year: 1447, month: 8, day: 29))
    }

    @Test func theMarkedDays() {
        let occasion = { (date: String) in HijriDate.of(date, offset: 0).flatMap(HijriOccasion.of) }
        #expect(occasion("2026-02-17") == nil)
        #expect(occasion("2026-02-18") == .ramadan)
        #expect(occasion("2026-03-19") == .ramadan)
        #expect(occasion("2026-03-20") == .eidAlFitr)
        #expect(occasion("2026-03-21") == nil)
        #expect(occasion("2026-05-25") == .tarwiyah)
        #expect(occasion("2026-05-26") == .arafah)
        #expect(occasion("2026-05-27") == .eidAlAdha)
        #expect(occasion("2026-05-28") == .tashriq)
        #expect(occasion("2026-05-30") == .tashriq)
        #expect(occasion("2026-05-31") == nil)
        #expect(occasion("2026-06-16") == .newYear)
    }

    /// Only these: no other day of the year is marked.
    @Test func noOtherDayIsMarked() {
        var marked: [HijriOccasion: Int] = [:]
        for month in 1...12 {
            for day in 1...30 {
                if let occasion = HijriOccasion.of(HijriDate(year: 1448, month: month, day: day)) {
                    marked[occasion, default: 0] += 1
                }
            }
        }
        #expect(marked == [.newYear: 1, .ramadan: 30, .eidAlFitr: 1, .tarwiyah: 1, .arafah: 1, .eidAlAdha: 1,
                           .tashriq: 3])
        #expect(HijriOccasion.allCases.filter(\.isHajj) == [.tarwiyah, .arafah, .eidAlAdha, .tashriq])
    }
}
