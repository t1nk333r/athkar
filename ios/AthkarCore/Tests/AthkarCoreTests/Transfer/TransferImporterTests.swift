@testable import AthkarCore
import Foundation
import GRDB
import Testing

private let today = "2026-10-04"
private let yesterday = "2026-10-03"
private let now = Instant.at("2026-10-04T06:00:00.000Z")
private let exported = Instant.at(TransferSamples.exportedAt)

private func importer(_ database: AppDatabase) throws -> TransferImporter {
    TransferImporter(database: database, collections: try RepoFile.content.adhkar, suwar: TransferFixtures.suwar)
}

/// Plans and applies `container` on 2026-10-04; returns the plan.
@discardableResult
private func transfer(_ container: TransferContainer, into database: AppDatabase, on date: String = today,
                      at instant: Date = now) throws -> TransferPlan {
    let importer = try importer(database)
    let plan = try importer.plan(container, today: date, now: instant)
    try importer.apply(plan, of: container)
    return plan
}

/// Phrase key → count on `date`.
private func tasbihCounts(_ database: AppDatabase, on date: String) throws -> [(String, Int)] {
    try database.tasbih.counts(on: date).map { ($0.phraseKey, $0.count) }
}

private func same(_ rows: [(String, Int)], _ expected: TransferJSON?) -> Bool {
    let members = expected?.members ?? []
    return rows.count == members.count && rows.allSatisfy { row in
        members.contains { TasbihPhrase.same($0.key, row.0) && $0.value.integer == row.1 }
    }
}

// MARK: - spec/transfer/fixtures/real-path.json

/// One case of `real-path.json`, with what of it the native receiver can reproduce.
struct TransferRealPathCase: Sendable, CustomTestStringConvertible {
    let name: String
    let input: TransferJSON
    let expected: TransferJSON

    var testDescription: String { name }

    /// The receiver holds the stores of a PWA: its equivalent spellings and reset epochs. The native stores keep no
    /// epochs, so a receiver case applies only when the PWA receiver has none (spec/transfer/transfer-v1.md §9.6).
    var applies: Bool {
        name.hasPrefix("sender") || receiverTasbih["resets"]?.members?.isEmpty == true
    }

    var date: String { name.hasSuffix("(in history)") ? yesterday : today }

    var receiverTasbih: TransferJSON {
        (try? TransferJSON.parse(input["receiver"]?["athkar-tasbih-v1"]?.string ?? "")) ?? .null
    }

    static var all: [TransferRealPathCase] {
        get throws {
            try (TransferFixtures.load("real-path.json")["cases"]?.array ?? []).map {
                TransferRealPathCase(name: $0["name"]!.string!, input: $0["input"]!, expected: $0["expected"]!)
            }
        }
    }
}

struct TransferRealPathTests {
    @Test func tenOfTheSixteenCasesApplyToTheNativeReceiver() throws {
        let cases = try TransferRealPathCase.all
        #expect(cases.count == 16)
        #expect(cases.filter(\.applies).count == 10)
    }

    @Test(arguments: try TransferRealPathCase.all.filter(\.applies))
    func theUnitHoldsThePWAsCount(_ fixture: TransferRealPathCase) throws {
        let database = try AppDatabase.inMemory()
        // The receiver's stored counts (no epochs: see `applies`), and its saved phrases.
        let receiver = fixture.receiverTasbih
        for (key, count) in receiver["counts"]?.members ?? [] {
            try database.tasbih.setCount(count.integer!, for: key, on: today, at: Instant.at("2026-10-04T05:00:00.000Z"))
        }
        for (day, counts) in receiver["history"]?.members ?? [] {
            for (key, count) in counts.members ?? [] {
                try database.tasbih.setCount(count.integer!, for: key, on: day, at: Instant.at("2026-10-03T05:00:00.000Z"))
            }
        }
        let custom = (receiver["custom"]?.array ?? []).map { $0.string! }
        if !custom.isEmpty { try database.settings.set(custom, for: .tasbihCustomPhrases) }

        let code = try #require(fixture.expected["codeTasbih"])
        try transfer(try TransferSamples.container(TransferSamples.code(tasbih: code.serialized)), into: database)

        let unit = TasbihPhrase.identity("c:يا رب")
        let rows = try database.tasbih.counts(on: fixture.date)
        #expect(rows.filter { TasbihPhrase.identity($0.phraseKey) == unit }.reduce(0) { $0 + $1.count }
            == fixture.expected["count"]?.integer)
        if fixture.name.hasPrefix("sender") {
            let stored = fixture.expected["storedTasbih"]
            #expect(same(try tasbihCounts(database, on: today), stored?["counts"]))
            #expect(same(try tasbihCounts(database, on: yesterday), stored?["history"]?[yesterday]))
        }
    }
}

// MARK: - Native receiver rules (spec/transfer/transfer-v1.md §9)

struct TransferImporterTests {
    private var typical: TransferContainer {
        get throws {
            let container = try TransferFixtures.load("codec.json")["roundTrip"]?.array?.first?["expected"]?["container"]
            return try TransferValidator.validateCode(try #require(container)).get()
        }
    }

    @Test func anEmptyDeviceReceivesEverythingOnce() throws {
        let database = try AppDatabase.inMemory()
        let plan = try transfer(try typical, into: database)
        #expect(!plan.isEmpty && !plan.hasResets)
        #expect(plan.warnings.isEmpty)

        let morning = try database.adhkar.session(on: today, period: .morning)
        #expect(morning.progress == ["morning-01": 1, "morning-02": 1])
        #expect(morning.completion == nil)
        let history = try database.adhkar.days(from: yesterday, through: yesterday)
        #expect(history.map(\.completionOrigin) == [.imported, .imported])
        #expect(history.map(\.completedAt) == [Instant.at("2026-10-03T15:00:00.000Z"), Instant.at("2026-10-03T03:00:00.000Z")]
            || history.map(\.completedAt) == [Instant.at("2026-10-03T03:00:00.000Z"), Instant.at("2026-10-03T15:00:00.000Z")])
        #expect(try database.suwar.readPages(on: today) == ["mulk-1-4", "mulk-5-8"])
        #expect(try database.suwar.suraDays(on: yesterday) == ["kahf": Instant.at("2026-10-03T18:00:00.000Z")])
        #expect(same(try tasbihCounts(database, on: today), try TransferJSON.parse(#"{"subhan":33,"c:يا حي يا قيوم":7}"#)))
        #expect(same(try tasbihCounts(database, on: yesterday), try TransferJSON.parse(#"{"hamd":100}"#)))
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == ["يا حي يا قيوم"])
        // Every row is stamped with the code's exportedAt.
        #expect(try database.tasbih.counts(on: today).allSatisfy { $0.updatedAt == exported })

        let rows = try changesOf(plan)
        #expect(rows.contains("adhkar \(today) morning addition"))
        #expect(rows.contains("adhkar \(yesterday) evening addition"))
        #expect(rows.contains("suwar \(today) mulk addition"))
        #expect(rows.contains("tasbih \(yesterday) hamd addition"))
        #expect(plan.addedPhrases == ["يا حي يا قيوم"])
    }

    private func changesOf(_ plan: TransferPlan) throws -> [String] {
        plan.changes.map { "\($0.store.rawValue) \($0.date) \($0.unit) \($0.kind == .reset ? "reset" : "addition")" }
    }

    @Test func importingTheSameCodeAgainChangesNothing() throws {
        let database = try AppDatabase.inMemory()
        let container = try typical
        try transfer(container, into: database)
        let first = try dump(database)
        let again = try importer(database).plan(container, today: today, now: now)
        #expect(again.isEmpty)
        #expect(again.changes.isEmpty && again.settings.isEmpty && !again.targetsAdded)
        try importer(database).apply(again, of: container)
        #expect(try dump(database) == first)
    }

    @Test func countsJoinToTheLargerAndKeepNewerProgressHere() throws {
        let database = try AppDatabase.inMemory()
        // Counted here after the code's 04:00 reset epoch for the morning.
        let later = Instant.at("2026-10-04T05:00:00.000Z")
        try database.adhkar.setCount(3, for: "morning-01", on: today, period: .morning, at: later)
        try database.tasbih.setCount(50, for: "subhan", on: today, at: later)
        try database.tasbih.setCount(2, for: "hamd", on: yesterday, at: later)
        let plan = try transfer(try typical, into: database)
        #expect(!plan.hasResets)
        let morning = try database.adhkar.session(on: today, period: .morning)
        #expect(morning.progress == ["morning-01": 3, "morning-02": 1])
        let rows = try database.adhkar.session(on: today, period: .morning)
        #expect(rows.progress["morning-01"] == 3)
        #expect(same(try tasbihCounts(database, on: today), try TransferJSON.parse(#"{"subhan":50,"c:يا حي يا قيوم":7}"#)))
        #expect(same(try tasbihCounts(database, on: yesterday), try TransferJSON.parse(#"{"hamd":100}"#)))
        #expect(try importer(database).plan(try typical, today: today, now: now).isEmpty)
    }

    @Test func aLaterResetOnTheOtherDeviceReplacesTheUnit() throws {
        let database = try AppDatabase.inMemory()
        // Counted here at 03:00, before the code's 04:00 morning reset.
        try database.adhkar.setCount(3, for: "morning-03", on: today, period: .morning,
                                     at: Instant.at("2026-10-04T03:00:00.000Z"))
        try database.adhkar.setCount(2, for: "evening-02", on: today, period: .evening,
                                     at: Instant.at("2026-10-04T03:00:00.000Z"))
        let plan = try transfer(try typical, into: database)
        #expect(try changesOf(plan).contains("adhkar \(today) morning reset"))
        let morning = try database.adhkar.session(on: today, period: .morning)
        #expect(morning.progress == ["morning-01": 1, "morning-02": 1])
        // The evening had no reset there: joined.
        #expect(try database.adhkar.session(on: today, period: .evening).progress == ["evening-02": 2])
        #expect(try importer(database).plan(try typical, today: today, now: now).isEmpty)
    }

    @Test func aResetWithNothingLeftThereClearsTheUnitHere() throws {
        let database = try AppDatabase.inMemory()
        try database.tasbih.setCount(9, for: "takbir", on: today, at: Instant.at("2026-10-04T03:00:00.000Z"))
        try database.suwar.markRead("kahf-1-4", of: "kahf", on: today, at: Instant.at("2026-10-04T03:00:00.000Z"))
        let code = TransferSamples.code(
            suwar: TransferSamples.suwar(resets: #"{"2026-10-04":"2026-10-04T04:00:00.000Z"}"#),
            tasbih: TransferSamples.tasbih(resets: #"{"2026-10-04|takbir":"2026-10-04T04:00:00.000Z"}"#))
        let plan = try transfer(try TransferSamples.container(code), into: database)
        #expect(Set(try changesOf(plan)) == ["suwar \(today) kahf reset", "tasbih \(today) takbir reset"])
        #expect(try database.tasbih.counts(on: today).isEmpty)
        #expect(try database.suwar.readPages(on: today).isEmpty)
    }

    @Test func completionsJoinAndAreNeverLostHere() throws {
        let database = try AppDatabase.inMemory()
        try database.adhkar.markComplete(on: today, period: .evening, origin: .manual,
                                         completedAt: Instant.at("2026-10-04T05:30:00.000Z"))
        let code = TransferSamples.code(envelope: TransferSamples.envelope(
            completedAt: #"{"morning":"2026-10-04T05:00:00.000Z","evening":null}"#,
            manual: #"{"morning":true,"evening":false}"#))
        try transfer(try TransferSamples.container(code), into: database)
        let morning = try database.adhkar.session(on: today, period: .morning)
        #expect(morning.completion?.completionOrigin == .manual)
        #expect(morning.completion?.completedAt == Instant.at("2026-10-04T05:00:00.000Z"))
        let evening = try database.adhkar.session(on: today, period: .evening)
        #expect(evening.completion?.completionOrigin == .manual)
    }

    @Test func aCodeFromALaterDayBringsOnlyTheDaysBeforeToday() throws {
        let database = try AppDatabase.inMemory()
        let code = TransferSamples.code(
            envelope: TransferSamples.envelope(date: "2026-10-05", exportedAt: "2026-10-04T22:00:00.000Z",
                                               morning: #"{"morning-01":1}"#),
            adhkarHistory: #"[{"date":"2026-10-04","morning":true,"evening":false,"morningAt":"2026-10-04T03:00:00.000Z","eveningAt":null},{"date":"2026-10-03","morning":true,"evening":false,"morningAt":"2026-10-03T03:00:00.000Z","eveningAt":null}]"#,
            suwar: TransferSamples.suwar(date: "2026-10-05"), tasbih: TransferSamples.tasbih(date: "2026-10-05"))
        let plan = try transfer(try TransferSamples.container(code), into: database)
        #expect(plan.warnings == [.future(date: "2026-10-05")])
        #expect(try database.adhkar.session(on: "2026-10-05", period: .morning).isEmpty)
        #expect(try database.adhkar.session(on: today, period: .morning).isEmpty)
        #expect(try database.adhkar.session(on: yesterday, period: .morning).completion != nil)
    }

    @Test func aCodeFromAnEarlierDayImportsItsDaysAsThey() throws {
        let database = try AppDatabase.inMemory()
        let code = TransferSamples.code(
            envelope: TransferSamples.envelope(date: "2026-10-02", exportedAt: "2026-10-02T06:00:00.000Z",
                                               morning: #"{"morning-01":1}"#),
            suwar: TransferSamples.suwar(date: "2026-10-02"),
            tasbih: TransferSamples.tasbih(date: "2026-10-02", counts: #"{"subhan":5}"#, firstUse: #"["subhan"]"#))
        let plan = try transfer(try TransferSamples.container(code), into: database)
        #expect(plan.warnings == [.stale(date: "2026-10-02")])
        #expect(try database.adhkar.session(on: "2026-10-02", period: .morning).progress == ["morning-01": 1])
        #expect(same(try tasbihCounts(database, on: "2026-10-02"), try TransferJSON.parse(#"{"subhan":5}"#)))
    }

    @Test func daysBeforeTheWindowAreTrimmed() throws {
        // The window of 2026-10-04 starts on 2026-09-05.
        let database = try AppDatabase.inMemory()
        let code = TransferSamples.code(
            envelope: TransferSamples.envelope(date: "2026-09-04", exportedAt: "2026-09-04T06:00:00.000Z"),
            adhkarHistory: #"[{"date":"2026-09-03","morning":true,"evening":false,"morningAt":null,"eveningAt":null}]"#,
            suwar: TransferSamples.suwar(date: "2026-09-04"), tasbih: TransferSamples.tasbih(date: "2026-09-04"))
        let plan = try importer(database).plan(try TransferSamples.container(code), today: today, now: now)
        #expect(plan.warnings == [.stale(date: "2026-09-04"), .trimmed])
        #expect(plan.isEmpty)
    }

    @Test func implausibleInstantsAreRefused() throws {
        let database = try AppDatabase.inMemory()
        for exportedAt in ["2026-10-05T07:00:00.000Z", "2019-12-31T23:59:59.999Z"] {
            let code = TransferSamples.code(envelope: TransferSamples.envelope(exportedAt: exportedAt))
            #expect(throws: TransferError(.clock)) {
                try importer(database).plan(try TransferSamples.container(code), today: today, now: now)
            }
        }
        let epoch = TransferSamples.code(adhkarResets: #"{"2026-10-04":"2026-10-05T06:00:00.001Z"}"#)
        #expect(throws: TransferError(.clock)) {
            try importer(database).plan(try TransferSamples.container(epoch), today: today, now: now)
        }
    }

    @Test func aMergePastTheTasbihBudgetIsRefusedWhole() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            for index in 0..<256 {
                try TasbihCount(localDate: today, phraseKey: "c:عبارة \(index)", count: 1, firstUse: index + 1,
                                updatedAt: now).insert(db)
            }
        }
        let code = TransferSamples.code(tasbih: TransferSamples.tasbih(counts: #"{"subhan":1}"#, firstUse: #"["subhan"]"#))
        #expect(throws: TransferError(.tooBig)) {
            try importer(database).plan(try TransferSamples.container(code), today: today, now: now)
        }
    }

    @Test func savedPhrasesPastEightAreDroppedWithTheirCounts() throws {
        let database = try AppDatabase.inMemory()
        let mine = (1...8).map { "عبارة \($0)" }
        try database.settings.set(mine, for: .tasbihCustomPhrases)
        let code = TransferSamples.code(tasbih: TransferSamples.tasbih(
            counts: #"{"c:يا رب":4,"subhan":2}"#, firstUse: #"["c:يا رب","subhan"]"#, custom: #"["يا رب"]"#))
        let plan = try transfer(try TransferSamples.container(code), into: database)
        #expect(plan.warnings == [.tasbihCap(phrases: ["يا رب"])])
        #expect(plan.addedPhrases.isEmpty)
        #expect(same(try tasbihCounts(database, on: today), try TransferJSON.parse(#"{"subhan":2}"#)))
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == mine)
    }

    @Test func aSavedSpellingHereNamesTheJoinedKey() throws {
        let database = try AppDatabase.inMemory()
        try database.settings.set(["يا رب"], for: .tasbihCustomPhrases)
        try database.tasbih.setCount(3, for: "c:يا رب", on: today, at: Instant.at("2026-10-04T05:00:00.000Z"))
        let code = TransferSamples.code(tasbih: TransferSamples.tasbih(
            counts: #"{"c:يَا رَبّ":5}"#, firstUse: #"["c:يَا رَبّ"]"#, custom: #"["يَا رَبّ"]"#))
        try transfer(try TransferSamples.container(code), into: database)
        #expect(same(try tasbihCounts(database, on: today), try TransferJSON.parse(#"{"c:يا رب":5}"#)))
        #expect(try database.settings.value(for: .tasbihCustomPhrases) == ["يا رب"])
    }

    @Test func settingsApplyOnlyWhereNothingIsStoredAndTheyDifferFromTheDefault() throws {
        let database = try AppDatabase.inMemory()
        try database.settings.set(TextSize.large, for: .textSize)
        let code = TransferSamples.code(envelope: TransferSamples.envelope(
            preferences: #"{"theme":"dark","textSize":"small","lineSpacing":"comfortable","haptics":false,"longOrder":"last","longOrderPromptAnswered":true}"#,
            calculation: #""calculationMethod":"umm-al-qura","asrSchool":"standard""#))
        let plan = try transfer(try TransferSamples.container(code), into: database)
        #expect(plan.settings == [.theme, .haptics, .longOrder, .longOrderPromptAnswered, .calculation])
        #expect(try database.settings.value(for: .theme) == .dark)
        #expect(try database.settings.value(for: .textSize) == .large)
        #expect(try database.settings.value(for: .haptics) == false)
        #expect(try database.settings.value(for: .calculationMethod) == .ummAlQura)
        #expect(try database.settings.value(for: .asrSchool) == .standard)
        // Reminders and location never transfer.
        #expect(try database.reader.read { try ReminderRule.fetchCount($0) } == 0)
        #expect(try database.reader.read { try LocationProfile.fetchCount($0) } == 0)
    }

    @Test func somethingRecordedAfterThePreviewStopsTheWrite() throws {
        let database = try AppDatabase.inMemory()
        let importer = try importer(database)
        let container = try typical
        let plan = try importer.plan(container, today: today, now: now)
        try database.tasbih.setCount(40, for: "subhan", on: today, at: Instant.at("2026-10-04T06:01:00.000Z"))
        let before = try dump(database)
        #expect(throws: TransferError(.changed)) { try importer.apply(plan, of: container) }
        #expect(try dump(database) == before)
    }

    @Test func aBackupFileImportsItsAdhkarOnly() throws {
        let database = try AppDatabase.inMemory()
        let file = try RepoFile.data("spec/backup/examples/athkar-pwa.athkarbackup")
        let container = try TransferCodec.decode(fileData: file).get()
        let date = container.date
        let instant = container.envelope.meta.exportedAt
        let plan = try transfer(container, into: database, on: date, at: instant)
        #expect(plan.warnings.first == .backup)
        #expect(try database.adhkar.session(on: date, period: .morning).progress.isEmpty == false
            || !(try database.adhkar.days(from: "2000-01-01", through: date)).isEmpty)
        #expect(try database.reader.read { try LocationProfile.fetchCount($0) } == 0)
        #expect(try importer(database).plan(container, today: date, now: instant).isEmpty)
    }
}
