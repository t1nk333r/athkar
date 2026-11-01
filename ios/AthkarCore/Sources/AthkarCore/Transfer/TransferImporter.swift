import Foundation
import GRDB

/// One sura of the «سور» pack as the receiver shows it: the transfer keeps only pages and suras it knows.
public struct SuwarOutline: Equatable, Sendable {
    public var id: String
    public var name: String
    public var pageIDs: [String]

    public init(id: String, name: String, pageIDs: [String]) {
        self.id = id
        self.name = name
        self.pageIDs = pageIDs
    }
}

/// What importing a transfer code would change here (the preview), and the exact writes that do it.
///
/// spec/transfer/transfer-v1.md §9 defines the native receiver's rules: units (adhkar `(date, period)`, suwar
/// `(date, sura)`, tasbih `(date, phrase)`) join (counts take the larger, marks and completions are kept from both)
/// unless the code carries a reset epoch later than everything stored here for the unit, which then takes the
/// code's unit whole. Imported rows are stamped with the code's `exportedAt`, so importing the same code again
/// changes nothing.
public struct TransferPlan: Equatable, Sendable {
    public enum Store: String, Sendable {
        case adhkar, suwar, tasbih
    }

    public struct AdhkarSummary: Equatable, Sendable {
        /// Non-review items at their target, and how many non-review items there are.
        public var done: Int
        public var total: Int
        /// Every counted item reached its target.
        public var countersComplete: Bool
        /// The period is recorded complete (by its counters, marked, or imported).
        public var complete: Bool
    }

    public enum Summary: Equatable, Sendable {
        case adhkar(AdhkarSummary)
        /// Read pages (the pack's order) and whether the sura is complete.
        case suwar(pages: [String], complete: Bool)
        /// The phrase's count that day.
        case tasbih(Int)
    }

    public struct Change: Equatable, Sendable {
        public enum Kind: Sendable {
            /// Something is added or raised; nothing here is lost.
            case addition
            /// The other device reset the unit after anything recorded here: the code's unit replaces it.
            case reset
        }

        public var kind: Kind
        public var store: Store
        public var date: String
        /// The period (`morning`, `evening`), the sura ID or the phrase key.
        public var unit: String
        /// The sura's name for suwar, else empty.
        public var name: String
        public var before: Summary
        public var after: Summary
        /// Adhkar: items whose count rose without reaching their target.
        public var risen: Int
    }

    public enum Warning: Equatable, Sendable {
        /// A backup file: no suwar, tasbih or reset epochs.
        case backup
        /// The code's day is after this device's: that day is not imported.
        case future(date: String)
        /// The code was made on an earlier day than this device's today.
        case stale(date: String)
        /// Days before this device's 31-day window are not imported.
        case trimmed
        /// Saved phrases that do not fit in «عباراتك» (at most eight); they and their counts are not imported.
        case tasbihCap(phrases: [String])
    }

    public enum SettingChange: String, Equatable, Sendable {
        case theme, textSize, lineSpacing, haptics, longOrder, longOrderPromptAnswered, calculation
    }

    public var source: TransferContainer.Source
    public var createdAt: Date
    /// This device's local date the plan was made for.
    public var today: String
    public var codeDate: String
    public var changes: [Change]
    public var addedPhrases: [String]
    public var settings: [SettingChange]
    /// Repetition choices («عدد التكرار») this device lacked are added; no visible progress changes.
    public var targetsAdded: Bool
    public var warnings: [Warning]

    let operations: [TransferImporter.Operation]

    public var hasResets: Bool { changes.contains { $0.kind == .reset } }
    public var isEmpty: Bool { operations.isEmpty }
}

/// Plans and applies a transfer code against the native stores (spec/transfer/transfer-v1.md §9).
public struct TransferImporter: Sendable {
    let database: AppDatabase
    let collections: SessionCollections
    let suwar: [SuwarOutline]

    /// An instant may be at most this far past this device's clock (clock skew between devices).
    static let clockSkew: TimeInterval = 86_400
    static let earliestExport = ISOInstant.parse("2020-01-01T00:00:00.000Z")!
    /// The tasbih budget over the 31-day window (spec §4): count keys per day and in all.
    static let maxTasbihKeysPerDay = 256
    static let maxTasbihKeys = 512

    public init(database: AppDatabase, collections: SessionCollections, suwar: [SuwarOutline]) {
        self.database = database
        self.collections = collections
        self.suwar = suwar
    }

    /// The preview of importing `container` on `today` (this device's local date) at `now`. Throws `clock` for a code
    /// with instants after this device's clock (plus a day) and `too-big` past the tasbih budget; nothing is written.
    public func plan(_ container: TransferContainer, today: String, now: Date = Date()) throws -> TransferPlan {
        try Self.checkClock(container, now: now)
        return try database.writer.read { db in try planned(container, today: today, in: db) }
    }

    /// Writes `plan` in one transaction, after checking that it was made on `today` (this device's local date now) and
    /// that the stores still give the same plan. Throws `changed` (nothing written) when the day has turned or
    /// something was recorded here since; plan again and show the new preview.
    public func apply(_ plan: TransferPlan, of container: TransferContainer, today: String) throws {
        guard plan.today == today else { throw TransferError(.changed) }
        try database.writer.write { db in
            let current = try planned(container, today: plan.today, in: db)
            guard current.operations == plan.operations else { throw TransferError(.changed) }
            for operation in plan.operations {
                try operation.execute(in: db)
            }
        }
    }

    // MARK: Checks

    static func checkClock(_ container: TransferContainer, now: Date) throws(TransferError) {
        let latest = now.addingTimeInterval(clockSkew)
        let envelope = container.envelope
        guard envelope.meta.exportedAt >= earliestExport else { throw TransferError(.clock) }
        var instants: [Date?] = [envelope.meta.exportedAt]
        if let adhkar = envelope.adhkar {
            instants += [adhkar.today.completedAt.morning, adhkar.today.completedAt.evening]
            instants += adhkar.history.flatMap { [$0.morningAt, $0.eveningAt] }
        }
        if let athkar = container.athkar {
            instants += athkar.adhkar.history.flatMap { [$0.morningAt, $0.eveningAt] }
            instants += athkar.adhkar.resets.map(\.at) + athkar.suwar.resets.map(\.at) + athkar.tasbih.resets.map(\.at)
            instants += athkar.suwar.completedAt.map(\.at)
            instants += athkar.suwar.history.flatMap { $0.suras.map(\.at) }
        }
        guard instants.allSatisfy({ ($0 ?? latest) <= latest }) else { throw TransferError(.clock) }
    }

    // MARK: Planning

    /// The span of days a code may change here: this device's 31-day window, never after its today.
    struct Window {
        let today: String
        let cutoff: String
        let codeDate: String
        var trimmed = false

        /// Whether a unit dated `date` takes part. Days before the window are noted (`trimmed`); a code dated
        /// after this device's today brings only the days before it.
        mutating func admits(_ date: String, contributes: Bool) -> Bool {
            if date > today || (codeDate > today && date >= today) { return false }
            if date < cutoff {
                if contributes { trimmed = true }
                return false
            }
            return true
        }
    }

    func planned(_ container: TransferContainer, today: String, in db: Database) throws -> TransferPlan {
        let stamp = container.envelope.meta.exportedAt
        var window = Window(today: today, cutoff: SessionState.historyCutoff(endingOn: today), codeDate: container.date)
        var changes: [TransferPlan.Change] = []
        var operations: [Operation] = []
        var targetsAdded = false

        if let adhkar = container.envelope.adhkar {
            let result = try planAdhkar(adhkar, resets: container.athkar?.adhkar.resets ?? [],
                                        history: container.athkar?.adhkar.history, stamp: stamp, window: &window, in: db)
            changes += result.changes
            operations += result.operations
            targetsAdded = result.targetsAdded
        }
        var addedPhrases: [String] = []
        var dropped: [String] = []
        if let athkar = container.athkar {
            let suwarResult = try planSuwar(athkar.suwar, stamp: stamp, window: &window, in: db)
            changes += suwarResult.changes
            operations += suwarResult.operations
            let tasbihResult = try planTasbih(athkar.tasbih, stamp: stamp, window: &window, in: db)
            changes += tasbihResult.changes
            operations += tasbihResult.operations
            addedPhrases = tasbihResult.added
            dropped = tasbihResult.dropped
        }
        let settings = try planSettings(container.envelope, stamp: stamp, in: db)
        operations += settings.operations

        var warnings: [TransferPlan.Warning] = []
        if container.source == .backup { warnings.append(.backup) }
        if container.date > today { warnings.append(.future(date: container.date)) }
        if container.date < today { warnings.append(.stale(date: container.date)) }
        if window.trimmed { warnings.append(.trimmed) }
        if !dropped.isEmpty { warnings.append(.tasbihCap(phrases: dropped)) }

        return TransferPlan(
            source: container.source, createdAt: stamp, today: today, codeDate: container.date,
            changes: changes.sorted { ($0.date, $0.store.rawValue, $0.unit) > ($1.date, $1.store.rawValue, $1.unit) },
            addedPhrases: addedPhrases, settings: settings.changes, targetsAdded: targetsAdded,
            warnings: warnings, operations: operations
        )
    }

    /// The epoch of a unit: the later of its day's epoch and its own.
    static func epoch(_ resets: TransferContainer.Resets, date: String, matching unit: (String) -> Bool) -> Date? {
        resets.filter { $0.date == date && ($0.unit.map(unit) ?? true) }.map(\.at).max()
    }

    static func earliest(_ instants: [Date?]) -> Date? {
        instants.compactMap { $0 }.min()
    }

    // MARK: Adhkar

    struct StoreResult {
        var changes: [TransferPlan.Change] = []
        var operations: [Operation] = []
        var targetsAdded = false
    }

    struct UnitKey: Hashable, Comparable {
        var date: String
        var unit: String

        static func < (lhs: Self, rhs: Self) -> Bool { (lhs.date, lhs.unit) < (rhs.date, rhs.unit) }
    }

    func planAdhkar(_ adhkar: BackupEnvelope.Adhkar, resets: TransferContainer.Resets,
                    history: [BackupEnvelope.Adhkar.HistoryEntry]?, stamp: Date, window: inout Window,
                    in db: Database) throws -> StoreResult {
        // The envelope as BackupImporter reads it, with a code's whole 31-day history in place of the newest seven.
        var source = adhkar
        if let history { source.history = history }
        var incoming: [UnitKey: AdhkarSession] = [:]
        for var session in BackupImporter.sessions(from: source, collections: collections) {
            // Items this version does not have are dropped, so repeated codes cannot grow the store.
            let known = Set(collections[session.period].map(\.id))
            session.progress = session.progress.filter { known.contains($0.key) }
            session.targets = session.targets.filter { known.contains($0.key) }
            incoming[UnitKey(date: session.localDate, unit: session.period.rawValue)] = session
        }
        var keys = Set(incoming.keys)
        for reset in resets {
            for period in Period.allCases where reset.unit == nil || reset.unit == period.rawValue {
                keys.insert(UnitKey(date: reset.date, unit: period.rawValue))
            }
        }

        var result = StoreResult()
        for key in keys.sorted() {
            let period = Period(rawValue: key.unit)!
            let theirs = incoming[key] ?? AdhkarSession(localDate: key.date, period: period)
            guard window.admits(key.date, contributes: !theirs.isEmpty) else { continue }
            let mine = try AdhkarRepository.session(in: db, on: key.date, period: period)
            let epoch = Self.epoch(resets, date: key.date) { $0 == key.unit }
            let rows = try AdhkarItemProgress
                .filter(Column("local_date") == key.date && Column("period") == period).fetchAll(db)
            let activity = (rows.map(\.updatedAt) + [mine.completion?.completedAt].compactMap { $0 }).max()
            let replaces = !mine.isEmpty && epoch.map { (activity ?? .distantPast) < $0 } == true

            var merged = AdhkarSession(localDate: key.date, period: period, targets: mine.targets)
            // Targets stay this device's; it gains only those it lacks, and never on a completed unit (a new target
            // could leave its completion unearned).
            if mine.completion == nil || replaces {
                for (id, target) in theirs.targets where merged.targets[id] == nil {
                    merged.targets[id] = target
                }
            }
            if replaces {
                merged.progress = theirs.progress
                merged.completion = theirs.completion
                if merged.completion != nil, !state(of: merged).countersComplete(period, in: collections),
                   merged.completion?.completionOrigin == .counters {
                    merged.completion = nil
                }
            } else {
                merged.progress = mine.progress.merging(theirs.progress) { max($0, $1) }
                merged.completion = joinedCompletion(mine: mine, theirs: theirs, merged: merged, stamp: stamp)
            }
            if merged.targets != mine.targets, merged.progress == mine.progress, merged.completion == mine.completion {
                result.targetsAdded = true
            }
            guard merged.progress != mine.progress || merged.targets != mine.targets
                    || merged.completion != mine.completion else { continue }

            let items = itemRows(merged, native: rows, stamp: stamp)
            result.operations.append(.adhkar(date: key.date, period: period, items: items,
                                             completion: merged.completion))
            let before = summary(mine)
            let after = summary(merged)
            let covers = mine.progress.allSatisfy { (merged.progress[$0.key] ?? 0) >= $0.value }
                && (mine.completion == nil || merged.completion != nil)
            let kind: TransferPlan.Change.Kind = replaces && !covers ? .reset : .addition
            guard kind == .reset || !merged.isEmpty, merged.progress != mine.progress || merged.completion != mine.completion
            else { continue }
            result.changes.append(.init(kind: kind, store: .adhkar, date: key.date, unit: key.unit, name: "",
                                        before: .adhkar(before), after: .adhkar(after),
                                        risen: risen(period, before: mine, after: merged)))
        }
        return result
    }

    /// Both devices' marks kept: complete when the joined counters complete the period or either side recorded it
    /// complete (never losing this device's completion). The instant is the earlier recorded one; a completion the
    /// join itself makes is stamped with the code's `exportedAt`.
    func joinedCompletion(mine: AdhkarSession, theirs: AdhkarSession, merged: AdhkarSession, stamp: Date)
        -> AdhkarDay? {
        let counters = !merged.progress.isEmpty && state(of: merged).countersComplete(merged.period, in: collections)
        let theirsMarked = theirs.completion.map { $0.completionOrigin != .counters } ?? false
        guard counters || mine.completion != nil || theirsMarked else { return nil }
        let sides = [mine.completion, theirsMarked || counters ? theirs.completion : nil].compactMap { $0 }
        let origin: CompletionOrigin = counters ? .counters : mine.completion?.completionOrigin
            ?? theirs.completion?.completionOrigin ?? .manual
        let at = sides.isEmpty ? stamp : Self.earliest(sides.map(\.completedAt))
        if let completion = mine.completion, completion.completionOrigin == origin, completion.completedAt == at {
            return completion
        }
        return AdhkarDay(localDate: merged.localDate, period: merged.period, completedAt: at, completionOrigin: origin)
    }

    func state(of session: AdhkarSession) -> SessionState {
        var state = SessionState.empty(date: session.localDate)
        state.progress[session.period] = .object(session.progress.mapValues { .number(Double($0)) })
        state.targets[session.period] = .object(session.targets.mapValues { .number(Double($0)) })
        return state
    }

    func summary(_ session: AdhkarSession) -> TransferPlan.AdhkarSummary {
        let state = state(of: session)
        let items = collections[session.period].filter { !$0.review }
        let done = items.filter { state.count(for: $0, in: session.period) >= state.target(for: $0, in: session.period) }
        return .init(done: done.count, total: items.count,
                     countersComplete: state.countersComplete(session.period, in: collections),
                     complete: session.completion != nil)
    }

    func risen(_ period: Period, before: AdhkarSession, after: AdhkarSession) -> Int {
        let was = state(of: before)
        let now = state(of: after)
        return collections[period].filter { item in
            guard !item.review else { return false }
            let old = was.count(for: item, in: period)
            let new = now.count(for: item, in: period)
            let target = now.target(for: item, in: period)
            return new > old && !(new >= target && old < was.target(for: item, in: period))
        }.count
    }

    /// The unit's item rows: an unchanged row keeps its stamp; a changed or new one takes the later of its stamp and
    /// the code's `exportedAt`.
    func itemRows(_ session: AdhkarSession, native: [AdhkarItemProgress], stamp: Date) -> [AdhkarItemProgress] {
        Set(session.progress.keys).union(session.targets.keys).sorted().map { id in
            let count = session.progress[id]
            let target = session.targets[id]
            if let row = native.first(where: { $0.itemId == id }) {
                if row.count == count, row.target == target { return row }
                return AdhkarItemProgress(localDate: session.localDate, period: session.period, itemId: id,
                                          count: count, target: target, updatedAt: max(row.updatedAt, stamp))
            }
            return AdhkarItemProgress(localDate: session.localDate, period: session.period, itemId: id, count: count,
                                      target: target, updatedAt: stamp)
        }
    }

    // MARK: Suwar

    func planSuwar(_ part: TransferContainer.Suwar, stamp: Date, window: inout Window, in db: Database) throws
        -> StoreResult {
        struct Unit {
            var pages: [String] = []
            var completedAt: Date?
            var complete = false
            /// A history unit carries only a completion.
            var history = false
        }
        var incoming: [UnitKey: Unit] = [:]
        for sura in suwar {
            let read = Set(part.read.first { $0.sura == sura.id }?.pages ?? [])
            let completed = part.completedAt.first { $0.sura == sura.id }?.at
            let pages = sura.pageIDs.filter(read.contains)
            if !pages.isEmpty || completed != nil {
                incoming[UnitKey(date: part.date, unit: sura.id)] = Unit(
                    pages: pages, completedAt: completed,
                    complete: !sura.pageIDs.isEmpty && pages.count == sura.pageIDs.count)
            }
        }
        for (date, suras) in part.history {
            for (id, at) in suras where suwar.contains(where: { $0.id == id }) {
                incoming[UnitKey(date: date, unit: id)] = Unit(completedAt: at, complete: true, history: true)
            }
        }
        var keys = Set(incoming.keys)
        for reset in part.resets {
            for sura in suwar where reset.unit == nil || reset.unit == sura.id {
                keys.insert(UnitKey(date: reset.date, unit: sura.id))
            }
        }

        var result = StoreResult()
        for key in keys.sorted() {
            let sura = suwar.first { $0.id == key.unit }!
            let theirs = incoming[key] ?? Unit()
            guard window.admits(key.date, contributes: !theirs.pages.isEmpty || theirs.complete) else { continue }
            let rows = try SuwarPageRead
                .filter(Column("local_date") == key.date && Column("sura_id") == sura.id).fetchAll(db)
            let day = try SuwarSuraDay.fetchOne(db, key: ["local_date": key.date, "sura_id": sura.id])
            let empty = rows.isEmpty && day == nil
            let activity = (rows.map(\.readAt) + [day?.completedAt].compactMap { $0 }).max()
            let epoch = Self.epoch(part.resets, date: key.date) { $0 == sura.id }
            let replaces = !empty && epoch.map { (activity ?? .distantPast) < $0 } == true

            let minePages = sura.pageIDs.filter { id in rows.contains { $0.pageId == id } }
            var pages: [String]
            var completion: SuwarSuraDay?
            if replaces {
                pages = theirs.pages
                completion = theirs.complete
                    ? SuwarSuraDay(localDate: key.date, suraId: sura.id, completedAt: theirs.completedAt ?? stamp) : nil
            } else {
                let union = Set(minePages).union(theirs.pages)
                pages = sura.pageIDs.filter(union.contains)
                let allRead = !sura.pageIDs.isEmpty && pages.count == sura.pageIDs.count
                let theirsComplete = theirs.complete && (theirs.history || allRead)
                if allRead || day != nil || theirsComplete {
                    let sides: [Date?] = [day?.completedAt, theirsComplete ? theirs.completedAt : nil]
                    let at = day == nil && !theirsComplete ? stamp : Self.earliest(sides) ?? stamp
                    completion = day?.completedAt == at ? day : SuwarSuraDay(localDate: key.date, suraId: sura.id,
                                                                            completedAt: at)
                }
            }
            guard pages != minePages || completion != day else { continue }
            let pageRows = pages.map { id in
                rows.first { $0.pageId == id }
                    ?? SuwarPageRead(localDate: key.date, suraId: sura.id, pageId: id, readAt: stamp)
            }
            result.operations.append(.suwar(date: key.date, sura: sura.id, pages: pageRows, completion: completion))
            let covers = minePages.allSatisfy(pages.contains) && (day == nil || completion != nil)
            let kind: TransferPlan.Change.Kind = replaces && !covers ? .reset : .addition
            guard kind == .reset || !pages.isEmpty || completion != nil else { continue }
            result.changes.append(.init(kind: kind, store: .suwar, date: key.date, unit: sura.id, name: sura.name,
                                        before: .suwar(pages: minePages, complete: day != nil),
                                        after: .suwar(pages: pages, complete: completion != nil), risen: 0))
        }
        return result
    }

    // MARK: Tasbih

    struct TasbihResult {
        var changes: [TransferPlan.Change] = []
        var operations: [Operation] = []
        var added: [String] = []
        var dropped: [String] = []
    }

    func planTasbih(_ part: TransferContainer.Tasbih, stamp: Date, window: inout Window, in db: Database) throws
        -> TasbihResult {
        var result = TasbihResult()
        // Saved phrases: this device's, then the code's it lacks, up to eight; a phrase that does not fit is dropped
        // with its counts and epochs.
        let mineCustom = try SettingsRepository.value(in: db, for: .tasbihCustomPhrases) ?? []
        var custom = mineCustom
        for phrase in part.custom where TasbihPhrase.findPhrase(phrase, custom: custom) == nil {
            if custom.count < TasbihPhrase.maxCustom { custom.append(phrase) } else { result.dropped.append(phrase) }
        }
        result.added = Array(custom.dropFirst(mineCustom.count))
        let droppedIDs = Set(result.dropped.map { TasbihPhrase.identity(TasbihPhrase.customKey($0)) })
        func takesPart(_ key: String) -> Bool {
            (TasbihPhrase.preset(key) != nil || TasbihPhrase.isCustomKey(key))
                && !droppedIDs.contains(TasbihPhrase.identity(key))
        }

        // The code's days as units: equivalent keys of one day reduce as the sender's own load does (only the keys
        // with the day's latest epoch count, summed).
        struct Incoming {
            var count = 0
            var spelling: String?
        }
        var incoming: [UnitKey: Incoming] = [:]
        var order: [UnitKey] = []
        for (date, counts) in [(part.date, part.counts)] + part.history {
            var groups: [String: [(key: String, count: Int, epoch: Date?)]] = [:]
            var identities: [String] = []
            for (key, count) in counts where takesPart(key) {
                let identity = TasbihPhrase.identity(key)
                if groups[identity] == nil { identities.append(identity) }
                let epoch = Self.epoch(part.resets, date: date) { TasbihPhrase.same($0, key) }
                groups[identity, default: []].append((key, count, epoch))
            }
            for identity in identities {
                let keys = groups[identity]!
                let latest = keys.map { $0.epoch ?? .distantPast }.max()!
                let kept = keys.filter { ($0.epoch ?? .distantPast) == latest }
                let unit = UnitKey(date: date, unit: identity)
                incoming[unit] = Incoming(count: min(kept.reduce(0) { $0 + $1.count }, TasbihCount.maxCount),
                                          spelling: kept.map(\.key).min { $0.utf8.lexicographicallyPrecedes($1.utf8) })
                order.append(unit)
            }
        }
        func unitEpoch(_ date: String, _ identity: String) -> Date? {
            Self.epoch(part.resets, date: date) { takesPart($0) && TasbihPhrase.identity($0) == identity }
        }

        // This device's rows of the dates the code touches.
        var dates = Set(incoming.keys.map(\.date))
        for reset in part.resets where reset.unit.map(takesPart) ?? true { dates.insert(reset.date) }
        var units = order
        for reset in part.resets {
            if let unit = reset.unit, takesPart(unit) {
                let key = UnitKey(date: reset.date, unit: TasbihPhrase.identity(unit))
                if !units.contains(key) { units.append(key) }
            }
        }
        var native: [String: [TasbihCount]] = [:]
        for date in dates.sorted() {
            native[date] = try TasbihCount.filter(Column("local_date") == date).order(Column("first_use")).fetchAll(db)
            if part.resets.contains(where: { $0.date == date && $0.unit == nil }) {
                for row in native[date]! {
                    let key = UnitKey(date: date, unit: TasbihPhrase.identity(row.phraseKey))
                    if !units.contains(key) { units.append(key) }
                }
            }
        }

        func keyOf(_ identity: String, mine: [TasbihCount], theirs: String?) -> String {
            if TasbihPhrase.preset(identity) != nil { return identity }
            if identity.hasPrefix("m:"),
               let saved = custom.first(where: { "m:" + TasbihPhrase.matchKey($0) == identity }) {
                return TasbihPhrase.customKey(saved)
            }
            return mine.map(\.phraseKey).min { $0.utf8.lexicographicallyPrecedes($1.utf8) } ?? theirs ?? identity
        }

        var finalRows = native
        for key in units {
            let theirs = incoming[key] ?? Incoming()
            guard window.admits(key.date, contributes: theirs.count > 0) else { continue }
            let day = finalRows[key.date] ?? []
            let mine = day.filter { TasbihPhrase.identity($0.phraseKey) == key.unit }
            let mineCount = min(mine.reduce(0) { $0 + $1.count }, TasbihCount.maxCount)
            let activity = mine.map(\.updatedAt).max()
            let replaces = !mine.isEmpty && unitEpoch(key.date, key.unit).map { (activity ?? .distantPast) < $0 } == true
            let after = replaces ? theirs.count : max(mineCount, theirs.count)
            guard after != mineCount else { continue }
            let spelling = keyOf(key.unit, mine: mine, theirs: theirs.spelling)
            var rows: [TasbihCount] = []
            var deleted: [String] = []
            let nextFirstUse = (day.map(\.firstUse).max() ?? 0) + 1
            if replaces {
                deleted = mine.map(\.phraseKey)
                if after > 0 {
                    rows = [TasbihCount(localDate: key.date, phraseKey: spelling, count: after,
                                        firstUse: mine.map(\.firstUse).min() ?? nextFirstUse, updatedAt: stamp)]
                }
            } else if var row = mine.first(where: { TasbihPhrase.same($0.phraseKey, spelling) }) ?? mine.first {
                row.count = min(row.count + after - mineCount, TasbihCount.maxCount)
                row.updatedAt = max(row.updatedAt, stamp)
                rows = [row]
            } else {
                rows = [TasbihCount(localDate: key.date, phraseKey: spelling, count: after, firstUse: nextFirstUse,
                                    updatedAt: stamp)]
            }
            finalRows[key.date] = day.filter { row in !deleted.contains { TasbihPhrase.same($0, row.phraseKey) }
                && !rows.contains { TasbihPhrase.same($0.phraseKey, row.phraseKey) } } + rows
            result.operations.append(.tasbih(date: key.date, deleting: deleted, rows: rows))
            let kind: TransferPlan.Change.Kind = replaces && after < mineCount ? .reset : .addition
            result.changes.append(.init(kind: kind, store: .tasbih, date: key.date, unit: spelling, name: "",
                                        before: .tasbih(mineCount), after: .tasbih(after), risen: 0))
        }
        if !result.added.isEmpty {
            result.operations.append(.custom(custom))
        }

        // The budget over this device's window, with the planned rows in place of the stored ones.
        let windowRows = try TasbihCount.filter(Column("local_date") >= window.cutoff && Column("local_date") <= window.today)
            .fetchAll(db)
        var byDate = Dictionary(grouping: windowRows, by: \.localDate)
        for (date, rows) in finalRows where date >= window.cutoff && date <= window.today { byDate[date] = rows }
        var keys: [[UInt8]] = []
        for rows in byDate.values {
            guard rows.count <= Self.maxTasbihKeysPerDay else { throw TransferError(.tooBig) }
            keys += rows.map { Array($0.phraseKey.utf8) }
        }
        guard Set(keys).count <= Self.maxTasbihKeys else { throw TransferError(.tooBig) }
        return result
    }

    // MARK: Settings

    /// A setting is written only where this device has no stored value, and only when the code's differs from the
    /// default shown here. Reminder switches, their last-shown dates and the location never transfer.
    func planSettings(_ envelope: BackupEnvelope, stamp: Date, in db: Database) throws
        -> (changes: [TransferPlan.SettingChange], operations: [Operation]) {
        var changes: [TransferPlan.SettingChange] = []
        var operations: [Operation] = []
        func put<Value: Equatable>(_ value: Value?, _ key: SettingKey<Value>, _ change: TransferPlan.SettingChange)
            throws {
            guard let value, value != key.defaultValue, try Setting.fetchOne(db, key: key.name) == nil else { return }
            changes.append(change)
            operations.append(.setting(Setting(key: key.name, valueJson: try SettingsRepository.json(value),
                                               origin: .athkarPWA, updatedAt: stamp)))
        }
        if let preferences = envelope.preferences {
            try put(preferences.theme, .theme, .theme)
            try put(preferences.textSize, .textSize, .textSize)
            try put(preferences.lineSpacing, .lineSpacing, .lineSpacing)
            try put(preferences.haptics, .haptics, .haptics)
            try put(preferences.longOrder, .longOrder, .longOrder)
            try put(preferences.longOrderPromptAnswered, .longOrderPromptAnswered, .longOrderPromptAnswered)
        }
        if let reminders = envelope.reminders,
           try Setting.fetchOne(db, key: SettingKey<CalculationMethod>.calculationMethod.name) == nil,
           try Setting.fetchOne(db, key: SettingKey<AsrSchool>.asrSchool.name) == nil,
           reminders.calculationMethod != .mwl || reminders.asrSchool != .standard {
            changes.append(.calculation)
            for (name, json) in [(SettingKey<CalculationMethod>.calculationMethod.name,
                                  try SettingsRepository.json(reminders.calculationMethod)),
                                 (SettingKey<AsrSchool>.asrSchool.name, try SettingsRepository.json(reminders.asrSchool))] {
                operations.append(.setting(Setting(key: name, valueJson: json, origin: .athkarPWA, updatedAt: stamp)))
            }
        }
        return (changes, operations)
    }

    // MARK: Writes

    /// One planned write. A unit's operation replaces everything stored for it with the planned rows.
    enum Operation: Equatable, Sendable {
        case adhkar(date: String, period: Period, items: [AdhkarItemProgress], completion: AdhkarDay?)
        case suwar(date: String, sura: String, pages: [SuwarPageRead], completion: SuwarSuraDay?)
        /// Deletes the rows of `deleting`, then writes `rows` (inserting or updating by key).
        case tasbih(date: String, deleting: [String], rows: [TasbihCount])
        case custom([String])
        case setting(Setting)

        func execute(in db: Database) throws {
            switch self {
            case let .adhkar(date, period, items, completion):
                let key = Column("local_date") == date && Column("period") == period
                try AdhkarItemProgress.filter(key).deleteAll(db)
                try AdhkarDay.filter(key).deleteAll(db)
                for item in items { try item.insert(db) }
                try completion?.insert(db)
            case let .suwar(date, sura, pages, completion):
                let key = Column("local_date") == date && Column("sura_id") == sura
                try SuwarPageRead.filter(key).deleteAll(db)
                try SuwarSuraDay.filter(key).deleteAll(db)
                for page in pages { try page.insert(db) }
                try completion?.insert(db)
            case let .tasbih(date, deleting, rows):
                for key in deleting {
                    _ = try TasbihCount.deleteOne(db, key: ["local_date": date, "phrase_key": key])
                }
                for row in rows { try row.upsert(db) }
            case let .custom(phrases):
                try Setting(key: SettingKey<[String]>.tasbihCustomPhrases.name,
                            valueJson: try SettingsRepository.json(phrases), origin: .native, updatedAt: Date()).upsert(db)
            case let .setting(setting):
                try setting.insert(db)
            }
        }
    }
}
