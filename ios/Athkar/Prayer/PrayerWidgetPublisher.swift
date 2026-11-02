import AthkarCore
import WidgetKit

/// Where ``PrayerTimesModel`` puts the times the lock-screen widget shows (``PrayerWidgetSnapshot``): the keychain in
/// the app, a recorder in tests.
@MainActor
protocol PrayerWidgetPublisher {
    /// Replaces the widget's times; `nil` deletes them.
    func publish(_ snapshot: PrayerWidgetSnapshot?)
}

/// ``PrayerWidgetStore``, then a reload of the widget's timeline when the times changed.
struct KeychainPrayerWidget: PrayerWidgetPublisher {
    func publish(_ snapshot: PrayerWidgetSnapshot?) {
        guard PrayerWidgetStore.load() != snapshot else { return }
        // Not reported: the app works without the widget, and a signature without a shared keychain group (see
        // PrayerWidgetStore) would fail on every change. The widget then asks for the app to be opened.
        guard (try? PrayerWidgetStore.save(snapshot)) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
