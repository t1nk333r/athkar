/// One day of ruqyah counters (`ruqyah-daily-v1.counts` in the ruqyah PWA) and the rules its deck applies to them.
public struct RuqyahProgress: Sendable, Equatable {
    public var date: String
    /// Segment ID → stored count, as read from `ruqyah_segment_progress`. Read through ``count(for:)``.
    public var counts: [String: Int]

    public init(date: String, counts: [String: Int] = [:]) {
        self.date = date
        self.counts = counts
    }

    /// `countFor(segment)` after `normalizeCounts`: the stored count clamped to `0…repeat`; missing is 0.
    public func count(for segment: RuqyahSegment) -> Int {
        min(max(counts[segment.id] ?? 0, 0), segment.repeatCount)
    }

    /// `isComplete(segment)`: read `repeat` times.
    public func isComplete(_ segment: RuqyahSegment) -> Bool {
        count(for: segment) >= segment.repeatCount
    }

    /// `allComplete()`: every segment read its `repeat` times, so the day is recorded as complete.
    public func allComplete(_ segments: [RuqyahSegment]) -> Bool {
        segments.allSatisfy(isComplete)
    }

    /// `firstIncompleteIndex()`: the first segment still to read; 0 when every segment is complete.
    public func firstIncompleteIndex(in segments: [RuqyahSegment]) -> Int {
        segments.firstIndex { !isComplete($0) } ?? 0
    }

    /// Readings done today across all segments (the progress bar's value, out of the sum of `repeat`).
    public func readings(in segments: [RuqyahSegment]) -> Int {
        segments.reduce(0) { $0 + count(for: $1) }
    }

    /// `countReading(segment)`: one more reading, unless the segment is already complete.
    ///
    /// - Returns: The new count, or `nil` when the segment was already complete and nothing changed.
    public mutating func countReading(_ segment: RuqyahSegment) -> Int? {
        guard !isComplete(segment) else { return nil }
        let next = count(for: segment) + 1
        counts[segment.id] = next
        return next
    }
}
