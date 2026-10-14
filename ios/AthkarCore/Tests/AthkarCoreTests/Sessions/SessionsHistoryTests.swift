import AthkarCore
import Foundation
import Testing

struct SessionsHistoryTests {
    private func entry(_ date: String, marker: String? = nil) -> SessionState.StoredValue {
        .object(["date": .string(date), "morning": .bool(true), "morningAt": marker.map { .string($0) } ?? .null])
    }

    private func normalize(date: String, history: [SessionState.StoredValue]) -> SessionState {
        .normalized(.object(["date": .string(date), "history": .array(history)]), today: "2026-10-01")
    }

    @Test func normalizationFiltersDatesWithoutSortingOrDeduplicating() {
        let dates = ["2026-03-15", "2026-03-01", "2026-03-15", "2026-04-01", "2026-03-31"]
        let garbage: [SessionState.StoredValue] = [
            .null, .number(1), .object(["date": .number(1)]),
            entry("2026-02-28"), entry("2026-02-29"), entry("2026-03-00"), entry("2026-03-32"),
            entry("2026-3-15"), entry("2026-03-15\n"),
        ]
        let state = normalize(date: "2026-03-31", history: garbage + dates.map { entry($0) })
        #expect(state.history.map(\.date) == dates)
        #expect(state.history.allSatisfy { $0.morning && !$0.evening })
    }

    @Test func normalizationTakesTheFirst31EntriesAfterFiltering() {
        let valid = (0..<33).map { entry("2026-09-29", marker: String($0)) }
        let state = normalize(date: "2026-09-30", history: [entry("2026-08-30"), entry("invalid")] + valid)
        #expect(state.history.count == 31)
        #expect(state.history.map(\.morningAt) == (0..<31).map { String($0) })
    }

    @Test(arguments: [
        ("2024-03-01", "2024-01-31", "2024-01-30"),
        ("2026-01-01", "2025-12-02", "2025-12-01"),
        ("0000-03-01", "0000-01-31", "0000-01-30"),
        ("0099-03-01", "0099-01-30", "0099-01-29"),
        // The PWA checks only the shape of the state's date; Date.setUTCFullYear rolls its overflow.
        ("2026-02-30", "2026-01-31", "2026-01-30"),
        ("2026-00-01", "2025-11-01", "2025-10-31"),
    ])
    func normalizationUsesTheStoredDateForTheCalendarWindow(date: String, cutoff: String, expired: String) {
        let state = normalize(date: date, history: [entry(expired), entry(cutoff)])
        #expect(state.date == date)
        #expect(state.history.map(\.date) == [cutoff])
    }

    @Test func rolloverUsesADateWindowWithoutAnEntryCap() throws {
        let collections = try RepoFile.content.adhkar
        var state = normalize(date: "2026-09-30", history: (0..<31).map { entry("2026-09-29", marker: String($0)) })
        let rolled = state.rolled(to: "2026-10-01", in: collections)
        #expect(rolled.history.count == 32)
        #expect(rolled.history.dropFirst() == state.history[...])

        // Replace every entry for the predecessor, leaving other duplicates and future dates in stored order.
        state.history = [
            .init(date: "2026-09-20", morning: true, evening: false),
            .init(date: state.date, morning: true, evening: true),
            .init(date: "2026-09-20", morning: false, evening: true),
            .init(date: state.date, morning: true, evening: false),
            .init(date: "2026-10-20", morning: false, evening: true),
            .init(date: "2026-09-01", morning: true, evening: true),
            .init(date: "2026-09-02", morning: true, evening: true),
        ]
        let next = state.rolled(to: "2026-10-02", in: collections)
        #expect(next.history == [state.historyEntry(in: collections), state.history[0], state.history[2],
                                 state.history[4], state.history[6]])
        #expect(state.rolled(to: "2026-12-01", in: collections).history.isEmpty)
    }

    @Test(arguments: [
        ("2026-03-09T06:59:59.999Z", ["2026-02-06", "2026-02-07"]),
        ("2026-03-09T07:00:00.000Z", ["2026-03-08", "2026-02-07"]),
    ])
    func loadAdvancesTheWindowAtLocalMidnightAfterDST(instant: String, expectedDates: [String]) throws {
        let state = normalize(date: "2026-03-08", history: [entry("2026-02-06"), entry("2026-02-07")])
        let stored = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        let loaded = SessionState.load(storage: [SessionState.storageKey: stored], now: Instant.at(instant),
                                       timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
                                       collections: try RepoFile.content.adhkar)
        #expect(loaded.history.map(\.date) == expectedDates)
    }

    @Test func loadAfterTheClockMovesBackKeepsTheFuturePredecessor() throws {
        let collections = try RepoFile.content.adhkar
        var state = SessionState.empty(date: "2026-09-25")
        state.manualCompletion.morning = true
        state.completedAt.morning = "2026-09-25T04:00:00.000Z"
        state.history = [
            .init(date: "2026-09-23", morning: true, evening: false),
            .init(date: "2026-09-24", morning: false, evening: true),
            .init(date: state.date, morning: false, evening: true),
        ]
        let stored = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        let loaded = SessionState.load(storage: [SessionState.storageKey: stored],
                                       now: Instant.at("2026-09-23T04:00:00.000Z"), timeZone: .gmt,
                                       collections: collections)
        #expect(loaded.date == "2026-09-23")
        #expect(loaded.history == [state.historyEntry(in: collections), state.history[0], state.history[1]])
        #expect(loaded.progress == .init(morning: [:], evening: [:]))
        #expect(loaded.manualCompletion == .init(morning: false, evening: false))
    }
}
