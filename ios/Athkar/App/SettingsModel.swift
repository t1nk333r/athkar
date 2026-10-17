import AthkarCore
import Foundation
import Observation

/// Reading and appearance settings (`settings` table). Each change is written at once; SQLite is the only store.
/// A change the database refuses is put back and reported once, so the settings always show what is saved.
@MainActor
@Observable
final class SettingsModel {
    var theme: Theme { didSet { write(theme, .theme) { self.theme = oldValue } } }
    var textSize: TextSize { didSet { write(textSize, .textSize) { self.textSize = oldValue } } }
    var lineSpacing: LineSpacing { didSet { write(lineSpacing, .lineSpacing) { self.lineSpacing = oldValue } } }
    var haptics: Bool { didSet { write(haptics, .haptics) { self.haptics = oldValue } } }
    var homePrayerRow: Bool { didSet { write(homePrayerRow, .homePrayerRow) { self.homePrayerRow = oldValue } } }
    private(set) var longOrder: LongOrder
    private(set) var longOrderPromptAnswered: Bool

    @ObservationIgnored private let repository: SettingsRepository
    @ObservationIgnored private let report: (any Error) -> Void
    /// Set while a refused value is put back, which the observers must not write again.
    @ObservationIgnored private var isRestoringValue = false

    init(repository: SettingsRepository, report: @escaping (any Error) -> Void) throws {
        self.repository = repository
        self.report = report
        theme = try repository.value(for: .theme)
        textSize = try repository.value(for: .textSize)
        lineSpacing = try repository.value(for: .lineSpacing)
        haptics = try repository.value(for: .haptics)
        homePrayerRow = try repository.value(for: .homePrayerRow)
        longOrder = try repository.value(for: .longOrder)
        longOrderPromptAnswered = try repository.value(for: .longOrderPromptAnswered)
    }

    /// Saves the long-order choice, then shows it. `false` when the save failed: the error is reported and nothing
    /// changes.
    @discardableResult
    func setLongOrder(_ value: LongOrder) -> Bool {
        do {
            try repository.set(value, for: .longOrder)
        } catch {
            report(error)
            return false
        }
        longOrder = value
        return true
    }

    /// Saves the answer to the one-time long-order question, the order and the answered flag together, then shows
    /// it. `false` when the save failed: the error is reported, nothing changes and the question stays unanswered.
    func answerLongOrderPrompt(_ value: LongOrder) -> Bool {
        do {
            try repository.setLongOrderDecision(value)
        } catch {
            report(error)
            return false
        }
        longOrder = value
        longOrderPromptAnswered = true
        return true
    }

    /// The observers' save. A refused value is put back by `restore`, without writing it again, before the error is
    /// reported.
    private func write<Value>(_ value: Value, _ key: SettingKey<Value>, restore: () -> Void) {
        guard !isRestoringValue else { return }
        do {
            try repository.set(value, for: key)
        } catch {
            restoreWithoutWriting(restore)
            report(error)
        }
    }

    private func restoreWithoutWriting(_ restore: () -> Void) {
        isRestoringValue = true
        defer { isRestoringValue = false }
        restore()
    }
}
