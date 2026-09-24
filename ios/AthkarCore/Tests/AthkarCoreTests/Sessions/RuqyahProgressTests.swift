import AthkarCore
import Testing

struct RuqyahProgressTests {
    let segments = [
        RuqyahSegment(id: "a", repeatCount: 1),
        RuqyahSegment(id: "b", repeatCount: 7),
        RuqyahSegment(id: "c", repeatCount: 1),
    ]

    /// `normalizeCounts`: stored values outside `0…repeat` read as the nearest bound.
    @Test func countsAreClampedToRepeat() {
        let progress = RuqyahProgress(date: "2026-09-23", counts: ["a": 5, "b": -2, "zzz": 3])
        #expect(segments.map(progress.count(for:)) == [1, 0, 0])
        #expect(progress.readings(in: segments) == 1)
    }

    @Test func readingStopsAtRepeatAndCompletesTheDay() {
        var progress = RuqyahProgress(date: "2026-09-23", counts: ["a": 1, "c": 1])
        #expect(progress.firstIncompleteIndex(in: segments) == 1)
        for expected in 1...7 {
            #expect(progress.countReading(segments[1]) == expected)
        }
        #expect(progress.countReading(segments[1]) == nil)
        #expect(progress.counts["b"] == 7)
        #expect(progress.allComplete(segments))
        // All complete: the deck opens on the first segment again.
        #expect(progress.firstIncompleteIndex(in: segments) == 0)
    }
}
