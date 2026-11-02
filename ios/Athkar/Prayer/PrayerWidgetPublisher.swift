import AthkarCore
import WidgetKit

/// Where ``PrayerTimesModel`` puts the times the lock-screen widget shows (``PrayerWidgetSnapshot``): the keychain in
/// the app, a recorder in tests.
@MainActor
protocol PrayerWidgetPublisher {
    /// Replaces the widget's times; `nil` deletes them.
    func publish(_ snapshot: PrayerWidgetSnapshot?)
}

/// ``PrayerWidgetStore``, written when the times changed, then a reload of the widget's timeline.
struct KeychainPrayerWidget: PrayerWidgetPublisher {
    func publish(_ snapshot: PrayerWidgetSnapshot?) {
        // A deletion always runs: `load()` cannot tell a missing item from one it cannot read.
        if snapshot == nil || PrayerWidgetStore.load() != snapshot {
            // Not reported: the app works without the widget, and a signature without a shared keychain group (see
            // PrayerWidgetStore) would fail on every change. The widget then asks for the app to be opened.
            guard (try? PrayerWidgetStore.save(snapshot)) != nil else { return }
        }
        // Also when nothing changed: a widget that could not read the item, before the first unlock, shows the times
        // again when the app is next opened.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
