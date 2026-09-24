import AthkarCore
import Foundation
import Testing

struct StorageSessionStoreTests {
    let database: AppDatabase
    let collections: SessionCollections
    let store: AdhkarSessionStore

    init() throws {
        database = try AppDatabase.inMemory()
        collections = try RepoFile.content.adhkar
        store = AdhkarSessionStore(database: database, collections: collections)
    }

    /// Saves, loads, and expects the loaded state to equal the in-memory one.
    func roundTrip(_ state: SessionState, at now: Date, _ step: String) throws {
        try store.save(state, at: now)
        #expect(try store.load(date: state.date) == state, "\(step)")
    }

    /// Every counted item of `period` at its target, except `short` items left one below.
    func fill(_ state: inout SessionState, _ period: Period, except short: Set<String> = []) {
        for item in collections[period] where !item.review {
            let target = state.target(for: item, in: period)
            state.progress[period][item.id] = .number(Double(short.contains(item.id) ? target - 1 : target))
        }
    }

    @Test func pwaOperationsSurviveSaveAndLoad() throws {
        let t1 = Instant.at("2026-09-22T04:30:00.123Z")
        let t2 = Instant.at("2026-09-22T05:00:00.456Z")
        let t3 = Instant.at("2026-09-22T15:00:00.789Z")

        var state = try store.load(date: "2026-09-22")
        #expect(state == .empty(date: "2026-09-22"))

        // Tapping through the morning deck, one item short, then the last tap.
        fill(&state, .morning, except: ["morning-25"])
        let result1 = state.syncCompletion(.morning, in: collections, now: t1)
        #expect(result1.complete == false)
        try roundTrip(state, at: t1, "morning one short")
        state.progress.morning["morning-25"] = .number(10)
        let result2 = state.syncCompletion(.morning, in: collections, now: t2)
        #expect(result2 == .init(complete: true, newlyCompleted: true))
        try roundTrip(state, at: t2, "morning complete by counters")
        #expect(try database.adhkar.session(on: "2026-09-22", period: .morning).completion?.completionOrigin == .counters)

        // Choosing a lower target for morning-20, as the target picker does (count clamped to the new target).
        state.targets.morning["morning-20"] = .number(10)
        state.progress.morning["morning-20"] = .number(10)
        let result3 = state.syncCompletion(.morning, in: collections, now: t3)
        #expect(result3.complete)
        try roundTrip(state, at: t3, "target changed")

        // Evening marked complete outside the app.
        let result4 = state.setManualCompletion(.evening, completed: true, in: collections, now: t3)
        #expect(result4)
        try roundTrip(state, at: t3, "evening manual")
        #expect(try database.adhkar.session(on: "2026-09-22", period: .evening).completion?.completionOrigin == .manual)

        // Next day: the finished day becomes history.
        let t4 = Instant.at("2026-09-23T03:00:00.000Z")
        var next = state.rolled(to: "2026-09-23", in: collections)
        try roundTrip(next, at: t4, "rolled")
        #expect(next.history == [.init(date: "2026-09-22", morning: true, evening: true,
                                       morningAt: "2026-09-22T05:00:00.456Z", eveningAt: "2026-09-22T15:00:00.789Z")])

        // Manual on and off again; then some taps, a target, and a day reset (targets survive it).
        let result5 = next.setManualCompletion(.morning, completed: true, in: collections, now: t4)
        #expect(result5)
        try roundTrip(next, at: t4, "manual on")
        let result6 = next.setManualCompletion(.morning, completed: false, in: collections, now: t4)
        #expect(result6)
        try roundTrip(next, at: t4, "manual off")
        next.progress.evening["evening-02"] = .number(2)
        next.targets.evening["evening-20"] = .number(1)
        _ = next.syncCompletion(.evening, in: collections, now: t4)
        try roundTrip(next, at: t4, "taps and target")
        next.resetDay()
        try roundTrip(next, at: t4, "reset day")
        #expect(next.targets.evening == ["evening-20": .number(1)])
    }

    @Test func rolledDayWithNothingCompleteIsNotHistory() throws {
        var state = SessionState.empty(date: "2026-09-22")
        state.progress.morning["morning-01"] = .number(1)
        try store.save(state, at: Instant.at("2026-09-22T04:00:00.000Z"))

        let rolled = state.rolled(to: "2026-09-23", in: collections)
        #expect(rolled.history == [.init(date: "2026-09-22", morning: false, evening: false)])
        try store.save(rolled, at: Instant.at("2026-09-23T04:00:00.000Z"))
        // spec/schema.md "Session state bridge": a both-false history entry is not representable.
        #expect(try store.load(date: "2026-09-23").history == [])
    }

    /// The PWA's week and everything resets through the database: history in scope disappears with all its rows;
    /// today keeps only its chosen targets.
    @Test func scopedResetRemovesHistoryAndResetsToday() throws {
        let adhkar = database.adhkar
        let t0 = Instant.at("2026-09-23T04:00:00.000Z")
        for date in ["2026-09-10", "2026-09-18", "2026-09-22"] {
            try adhkar.markComplete(on: date, period: .morning, origin: .counters, completedAt: t0)
            try adhkar.setTarget(10, for: "morning-20", on: date, period: .morning, at: t0)
        }
        var state = try store.load(date: "2026-09-23")
        state.progress.morning["morning-01"] = .number(1)
        state.targets.evening["evening-20"] = .number(1)
        state.setManualCompletion(.evening, completed: true, in: collections, now: t0)
        try store.save(state, at: t0)
        #expect(try store.load(date: "2026-09-23").history.map(\.date) == ["2026-09-22", "2026-09-18", "2026-09-10"])

        let now = Instant.at("2026-09-23T12:00:00.000Z")
        let window = state.resetWeek(now: now, timeZone: .gmt)
        #expect(HistoryRemoval.week(endingAt: now, in: .gmt) == .dates(from: window.last!, through: window.first!))
        try store.save(state, removing: .week(endingAt: now, in: .gmt), at: now)
        let afterWeek = try store.load(date: "2026-09-23")
        #expect(afterWeek == state)
        #expect(afterWeek.history.map(\.date) == ["2026-09-10"])
        #expect(afterWeek.targets.evening == ["evening-20": .number(1)] && afterWeek.progress.morning == [:])
        #expect(try adhkar.session(on: "2026-09-18", period: .morning) == AdhkarSession(localDate: "2026-09-18",
                                                                                       period: .morning))
        #expect(try adhkar.session(on: "2026-09-10", period: .morning).targets == ["morning-20": 10])

        state.resetEverything()
        try store.save(state, removing: .all, at: now)
        #expect(try store.load(date: "2026-09-23") == state)
        #expect(try adhkar.days(from: "0000-01-01", through: "9999-12-31") == [])
        #expect(try adhkar.session(on: "2026-09-10", period: .morning).targets == [:])
    }

    @Test func historyIsTheSevenNewestEarlierCompletedDays() throws {
        for day in 10...20 {
            try database.adhkar.markComplete(on: "2026-09-\(day)", period: .evening, origin: .imported,
                                             completedAt: nil)
        }
        try database.adhkar.setCount(1, for: "morning-01", on: "2026-09-09", period: .morning)
        let history = try store.load(date: "2026-09-18").history
        #expect(history.map(\.date) == ["2026-09-17", "2026-09-16", "2026-09-15", "2026-09-14", "2026-09-13",
                                        "2026-09-12", "2026-09-11"])
        #expect(history.allSatisfy { !$0.morning && $0.evening && $0.eveningAt == nil })
    }

    @Test func unchangedSaveKeepsRowsAndStamps() throws {
        var state = SessionState.empty(date: "2026-09-22")
        fill(&state, .morning)
        _ = state.syncCompletion(.morning, in: collections, now: Instant.at("2026-09-22T04:00:00.000Z"))
        try store.save(state, at: Instant.at("2026-09-22T04:00:00.000Z"))
        let before = try dump(database)
        try store.save(state, at: Instant.at("2026-09-22T09:00:00.000Z"))
        #expect(try dump(database) == before)
    }

    /// Values the PWA can hold but the tables cannot are reduced to what the rules read from them.
    @Test func unrepresentableValuesKeepTheirRuleOutcome() throws {
        var state = SessionState.empty(date: "2026-09-22")
        state.progress.morning = [
            "morning-01": .string("1"), "morning-02": .number(2.9), "morning-03": .string("abc"),
            "morning-04": .number(-1), "morning-05": .bool(true), "morning-20": .string(" 10 "),
        ]
        state.targets.morning = ["morning-20": .string("10"), "morning-21": .number(2.5)]
        state.completedAt.evening = "not an instant"
        state.manualCompletion.evening = true
        try store.save(state, at: Instant.at("2026-09-22T04:00:00.000Z"))

        let loaded = try store.load(date: "2026-09-22")
        #expect(loaded != state)
        for period in Period.allCases {
            for item in collections[period] {
                #expect(loaded.count(for: item, in: period) == state.count(for: item, in: period), "\(item.id)")
                #expect(loaded.target(for: item, in: period) == state.target(for: item, in: period), "\(item.id)")
            }
            #expect(loaded.isComplete(period, in: collections) == state.isComplete(period, in: collections))
        }
        #expect(loaded.progress.morning == ["morning-01": .number(1), "morning-02": .number(2),
                                            "morning-05": .number(1), "morning-20": .number(10)])
        #expect(loaded.targets.morning == ["morning-20": .number(10)])
        #expect(loaded.completedAt.evening == nil && loaded.manualCompletion.evening)
    }

    @Test func importedPWAFileLoadsAsTheExportedState() throws {
        try BackupImporter(database: database, content: RepoFile.content)
            .importBackup(try RepoFile.data("spec/backup/examples/athkar-pwa.athkarbackup"))
        let state = try store.load(date: "2026-09-23")
        #expect(state.progress.morning == ["morning-01": .number(1), "morning-02": .number(3),
                                           "morning-20": .number(250)])
        #expect(state.targets.morning == ["morning-20": .number(10)])
        #expect(state.manualCompletion == .init(morning: false, evening: true))
        #expect(state.completedAt == .init(morning: nil, evening: nil))
        #expect(state.history == [.init(date: "2026-09-22", morning: true, evening: false,
                                        morningAt: "2026-09-22T17:38:40.481Z", eveningAt: nil)])
        // Saving the loaded state changes nothing.
        let before = try dump(database)
        try store.save(state, at: Instant.at("2026-09-24T00:00:00.000Z"))
        #expect(try dump(database) == before)
    }
}

/// `spec/sessions/fixtures/completion-sync.json` through the database: every case uses clean numbers.
struct StorageSessionStoreFixtureTests {
    struct Fixture: Decodable {
        struct Input: Decodable {
            var now: String?
            var state: SessionState?
            var collections: SessionCollections?
            var operation: Operation?
        }

        struct Operation: Decodable {
            var function: String
            var period: Period
            var completed: Bool?
        }

        struct Expected: Decodable {
            var state: SessionState
        }

        struct Case: Decodable {
            var name: String
            var input: Input
            var expected: Expected
        }

        var defaultInput: Input
        var cases: [Case]
    }

    static let fixture: Fixture = {
        let data = try! RepoFile.data("spec/sessions/fixtures/completion-sync.json")
        return try! JSONDecoder().decode(Fixture.self, from: data)
    }()

    @Test(arguments: fixture.cases.indices)
    func caseSurvivesSaveAndLoad(index: Int) throws {
        let testCase = Self.fixture.cases[index]
        let input = testCase.input
        let collections = try #require(input.collections ?? Self.fixture.defaultInput.collections)
        let state = try #require(input.state)
        let operation = try #require(input.operation)
        let now = Instant.at(try #require(input.now))
        #expect(state.history.isEmpty, "\(testCase.name): history would need seeding")

        let store = AdhkarSessionStore(database: try AppDatabase.inMemory(), collections: collections)
        func apply(_ state: SessionState) -> SessionState {
            var state = state
            switch operation.function {
            case "syncCompletionState":
                _ = state.syncCompletion(operation.period, in: collections, now: now)
            case "setManualCompletion":
                state.setManualCompletion(operation.period, completed: operation.completed ?? false,
                                          in: collections, now: now)
            default:
                Issue.record("\(testCase.name): unknown operation \(operation.function)")
            }
            return state
        }

        // The input is representable iff every period has completedAt exactly when it is complete; the
        // fixture's "reset below target" input is a stale pre-sync state that is not.
        let representable = Period.allCases.allSatisfy {
            (state.completedAt[$0] != nil) == state.isComplete($0, in: collections)
        }
        var current = state
        if representable {
            try store.save(state, at: now)
            current = try store.load(date: state.date)
            #expect(current == state, "\(testCase.name): input")
        }
        try store.save(apply(current), at: now)
        #expect(try store.load(date: state.date) == testCase.expected.state, "\(testCase.name): result")
    }
}
