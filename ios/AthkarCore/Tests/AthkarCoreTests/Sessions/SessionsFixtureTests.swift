import AthkarCore
import Foundation
import Testing

/// Runs every case of the PWA's golden session fixtures (`spec/sessions/fixtures/`) against the Swift port.
@Suite("Session fixtures")
struct SessionsFixtureTests {
    private struct StateInput: Decodable {
        let collections: SessionCollections
        let state: SessionState
    }

    private struct StateOutput: Decodable {
        let state: SessionState
    }

    // MARK: period-is-complete.json

    private struct PeriodCompletion: Decodable, Equatable {
        let countersComplete: Bool
        let manuallyComplete: Bool
        let complete: Bool
    }

    @Test(arguments: try SessionsFixtures.cases("period-is-complete.json"))
    func periodIsComplete(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: StateInput.self)
        let expected = try fixture.expected(as: SessionPeriods<PeriodCompletion>.self)
        for period in Period.allCases {
            let actual = PeriodCompletion(
                countersComplete: input.state.countersComplete(period, in: input.collections),
                manuallyComplete: input.state.isManuallyComplete(period),
                complete: input.state.isComplete(period, in: input.collections)
            )
            #expect(actual == expected[period], "\(fixture.name) [\(period)]")
        }
    }

    // MARK: roll-state-to-date.json

    private struct RollInput: Decodable {
        let collections: SessionCollections
        let state: SessionState
        let nextDate: String
    }

    @Test(arguments: try SessionsFixtures.cases("roll-state-to-date.json"))
    func rollStateToDate(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: RollInput.self)
        let expected = try fixture.expected(as: StateOutput.self)
        #expect(input.state.rolled(to: input.nextDate, in: input.collections) == expected.state, "\(fixture.name)")
    }

    // MARK: load-state.json

    private struct LoadInput: Decodable {
        let collections: SessionCollections
        let timeZone: String
        let now: String
        let storage: [String: String]
    }

    @Test(arguments: try SessionsFixtures.cases("load-state.json"))
    func loadState(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: LoadInput.self)
        let expected = try fixture.expected(as: StateOutput.self)
        let loaded = SessionState.load(
            storage: input.storage,
            now: try SessionsFixtures.instant(input.now),
            timeZone: try SessionsFixtures.timeZone(input.timeZone),
            collections: input.collections
        )
        #expect(loaded == expected.state, "\(fixture.name)")
    }

    // MARK: build-deck.json

    private struct DeckInput: Decodable {
        let collections: SessionCollections
        let state: SessionState
        let longAdhkarLast: Bool
    }

    private struct DeckOutput: Decodable, Equatable {
        let deck: [String]
        let longItems: [String]
    }

    @Test(arguments: try SessionsFixtures.cases("build-deck.json"))
    func buildDeck(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: DeckInput.self)
        let expected = try fixture.expected(as: SessionPeriods<DeckOutput>.self)
        for period in Period.allCases {
            let actual = DeckOutput(
                deck: input.state.deck(period, in: input.collections, longAdhkarLast: input.longAdhkarLast).map(\.id),
                longItems: input.collections[period].filter { input.state.isLongDhikr($0, in: period) }.map(\.id)
            )
            #expect(actual == expected[period], "\(fixture.name) [\(period)]")
        }
    }

    // MARK: first-incomplete-index.json

    private struct IndexOutput: Decodable, Equatable {
        let index: Int
        let itemId: String?
    }

    @Test(arguments: try SessionsFixtures.cases("first-incomplete-index.json"))
    func firstIncompleteIndex(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: DeckInput.self)
        let expected = try fixture.expected(as: SessionPeriods<IndexOutput>.self)
        for period in Period.allCases {
            let deck = input.state.deck(period, in: input.collections, longAdhkarLast: input.longAdhkarLast)
            let index = input.state.firstIncompleteIndex(in: deck, period: period)
            let actual = IndexOutput(index: index, itemId: deck.indices.contains(index) ? deck[index].id : nil)
            #expect(actual == expected[period], "\(fixture.name) [\(period)]")
        }
    }

    // MARK: completion-sync.json

    private struct CompletionInput: Decodable {
        struct Operation: Decodable {
            let function: String
            let period: Period
            let completed: Bool?
        }

        let collections: SessionCollections
        let state: SessionState
        let now: String
        let operation: Operation
    }

    private struct CompletionOutput: Decodable {
        let returned: SessionState.CompletionSync?
        let state: SessionState
    }

    @Test(arguments: try SessionsFixtures.cases("completion-sync.json"))
    func completionSync(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: CompletionInput.self)
        let expected = try fixture.expected(as: CompletionOutput.self)
        let now = try SessionsFixtures.instant(input.now)
        var state = input.state
        var returned: SessionState.CompletionSync?
        switch input.operation.function {
        case "syncCompletionState":
            returned = state.syncCompletion(input.operation.period, in: input.collections, now: now)
        case "setManualCompletion":
            let completed = try #require(input.operation.completed as Bool?, "\(fixture.name): setManualCompletion without completed")
            state.setManualCompletion(input.operation.period, completed: completed, in: input.collections, now: now)
        default:
            Issue.record("\(fixture.name): unknown operation \(input.operation.function)")
        }
        #expect(returned == expected.returned, "\(fixture.name)")
        #expect(state == expected.state, "\(fixture.name)")
    }

    // MARK: scoped-reset.json

    private struct ResetInput: Decodable {
        let collections: SessionCollections
        let timeZone: String
        let now: String
        let scope: String
        let state: SessionState
    }

    private struct ResetOutput: Decodable {
        let hasResettableStateBefore: Bool
        let deletedHistoryDates: [String]?
        let state: SessionState
    }

    @Test(arguments: try SessionsFixtures.cases("scoped-reset.json"))
    func scopedReset(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: ResetInput.self)
        let expected = try fixture.expected(as: ResetOutput.self)
        var state = input.state
        #expect(state.hasResettableState(in: input.collections) == expected.hasResettableStateBefore, "\(fixture.name)")
        var window: [String]?
        switch input.scope {
        case "day":
            state.resetDay()
        case "week":
            window = state.resetWeek(now: try SessionsFixtures.instant(input.now), timeZone: try SessionsFixtures.timeZone(input.timeZone))
        case "everything":
            state.resetEverything()
        default:
            Issue.record("\(fixture.name): unknown scope \(input.scope)")
        }
        #expect(window == expected.deletedHistoryDates, "\(fixture.name)")
        #expect(state == expected.state, "\(fixture.name)")
    }
}
