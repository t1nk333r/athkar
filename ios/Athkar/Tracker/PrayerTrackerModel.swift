import AthkarCore
import Foundation
import Observation

/// The prayer tracker (spec/tracker/tracker.md): the records of the days on screen, the commands and their undo, and
/// the calendar month. Every command goes through ``PrayerRecordRepository/apply(_:to:context:)``, so a «record»
/// sent twice stores one record.
@MainActor
@Observable
final class PrayerTrackerModel {
    /// The last change a quick log or a sheet made, which «تراجع» restores.
    struct Change: Equatable, Identifiable {
        let id = UUID()
        let occurrence: PrayerOccurrence
        /// The entry before the change.
        let previous: PrayerEntry
        /// The entry after it, as the undo bar names it.
        let entry: PrayerEntry
    }

    /// The change «تراجع» would undo, or `nil` once it is dismissed or undone.
    private(set) var lastChange: Change?
    /// Bumped on every write, so views reading records refresh.
    private(set) var revision = 0
    /// Called after every write, a cleared day and a reload: the reminders replan, since a recorded prayer gets no
    /// notification (NATIVE_APP_PLAN.md §7.5).
    @ObservationIgnored var didWrite: @MainActor () -> Void = {}

    @ObservationIgnored private var cache: [String: [ObligatoryPrayer: PrayerRecord]] = [:]
    private let repository: PrayerRecordRepository
    private let report: (any Error) -> Void
    /// The clock and the zone the tracker's dates are in: the prayer times' zone.
    private let clock: @MainActor () -> (now: Date, zone: TimeZone)
    /// What a new record captures: the occurrence's calculated time and the calculation profile.
    private let metadata: @MainActor (PrayerOccurrence) -> (scheduledAt: Date?, profileVersion: String)

    init(repository: PrayerRecordRepository, report: @escaping (any Error) -> Void,
         clock: @escaping @MainActor () -> (now: Date, zone: TimeZone),
         metadata: @escaping @MainActor (PrayerOccurrence) -> (scheduledAt: Date?, profileVersion: String)) {
        self.repository = repository
        self.report = report
        self.clock = clock
        self.metadata = metadata
    }

    /// The civil date of now in the tracker's zone.
    var today: String {
        let (now, zone) = clock()
        return SessionCalendar.localDate(of: now, in: zone)
    }

    var zone: TimeZone { clock().zone }

    /// The records of `date`, by prayer. A day without records reads as all `unrecorded`.
    func records(on date: String) -> [ObligatoryPrayer: PrayerRecord] {
        _ = revision
        if let cached = cache[date] { return cached }
        do {
            let records = Dictionary(uniqueKeysWithValues: try repository.records(on: date).map { ($0.prayerKey, $0) })
            cache[date] = records
            return records
        } catch {
            report(error)
            return [:]
        }
    }

    func entry(_ occurrence: PrayerOccurrence) -> PrayerEntry {
        records(on: occurrence.date)[occurrence.prayer]?.entry ?? .unrecorded
    }

    func record(_ occurrence: PrayerOccurrence) -> PrayerRecord? {
        records(on: occurrence.date)[occurrence.prayer]
    }

    /// Whether `date` can be edited: a real day that is not after today.
    func isEditable(_ date: String) -> Bool {
        LocalDate.epochDay(date) != nil && date <= today
    }

    // MARK: Commands

    /// The row's one-tap log: «صلّيتُها», with no timing and, on a Friday, no Jumu'ah or Dhuhr choice. Offers undo.
    @discardableResult
    func quickLog(_ occurrence: PrayerOccurrence) -> Bool {
        apply(.record(noon: nil), to: occurrence)
    }

    /// Applies `command` and keeps the previous entry for «تراجع». Returns whether anything changed; a refused command
    /// (a future day) changes nothing.
    @discardableResult
    func apply(_ command: PrayerCommand, to occurrence: PrayerOccurrence) -> Bool {
        let previous = entry(occurrence)
        guard let record = write(command, to: occurrence) else { return false }
        lastChange = Change(occurrence: occurrence, previous: previous, entry: record.entry)
        return true
    }

    /// «تراجع»: the entry before the last change, back through the same idempotent command path.
    func undo() {
        guard let change = lastChange else { return }
        lastChange = nil
        _ = write(.restore(change.previous), to: change.occurrence)
    }

    func dismissUndo() {
        lastChange = nil
    }

    /// «مسح اليوم», after its confirmation: every prayer of `date` back to unrecorded. The rows keep their metadata.
    @discardableResult
    func clearDay(_ date: String) -> Bool {
        let (now, zone) = clock()
        let context = PrayerCommandContext(now: now, zone: zone, scheduledAt: nil, profileVersion: "-")
        do {
            let changed = try repository.clearDay(date, context: context)
            if lastChange?.occurrence.date == date { lastChange = nil }
            refresh(date)
            return changed
        } catch is PrayerCommandRefusal {
            return false
        } catch {
            report(error)
            return false
        }
    }

    /// «سجّل الصلاة» on a prayer reminder: the same idempotent «record» as the row's quick log, for the reminder's own
    /// occurrence. It is not offered for undo: the change was made away from the screen that shows «تراجع».
    @discardableResult
    func logFromReminder(_ occurrence: PrayerOccurrence) -> Bool {
        write(.record(noon: nil), to: occurrence) != nil
    }

    /// Records changed elsewhere (a later import, the day turning): read them again.
    func reload() {
        cache = [:]
        revision += 1
        didWrite()
    }

    /// The state of every recorded occurrence from `date` through the `days - 1` days after it: what the reminder
    /// planner skips. Nothing on a read failure, which is reported.
    func states(from date: String, days: Int) -> [PrayerOccurrence: PrayerRecordState] {
        guard days > 0, let last = LocalDate.adding(days - 1, to: date) else { return [:] }
        do {
            return ReminderPlanner.prayerStates(try repository.records(from: date, through: last))
        } catch {
            report(error)
            return [:]
        }
    }

    // MARK: Calendar

    /// The calendar summary of `month` (`YYYY-MM`), read with the adhkar and ruqyah completions.
    func month(_ month: String) -> PrayerCalendarMonth? {
        _ = revision
        do {
            return try repository.month(month, today: today)
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Writing

    private func write(_ command: PrayerCommand, to occurrence: PrayerOccurrence) -> PrayerRecord? {
        let (now, zone) = clock()
        let (scheduledAt, profileVersion) = metadata(occurrence)
        let context = PrayerCommandContext(now: now, zone: zone, scheduledAt: scheduledAt,
                                           profileVersion: profileVersion)
        do {
            guard case let .changed(record) = try repository.apply(command, to: occurrence, context: context) else {
                return nil
            }
            refresh(occurrence.date)
            return record
        } catch is PrayerCommandRefusal {
            return nil
        } catch {
            report(error)
            return nil
        }
    }

    private func refresh(_ date: String) {
        cache[date] = nil
        revision += 1
        didWrite()
    }
}
