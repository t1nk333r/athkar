import AthkarCore
import Security
import XCTest
@testable import Athkar

/// The keychain item the lock-screen widget reads (``PrayerWidgetStore``), in the simulator's keychain. A host the
/// keychain refuses (an unsigned build can be) skips: whether the widget shares the item needs a device.
final class PrayerWidgetStoreTests: XCTestCase {
    private let snapshot = PrayerWidgetSnapshot(zone: "Asia/Riyadh", prayers: [
        .init(prayer: .fajr, adhan: Date(timeIntervalSince1970: 1_760_400_000),
              iqama: Date(timeIntervalSince1970: 1_760_401_500)),
    ])

    /// Adds and deletes the item first: a keychain that refuses the host refuses both.
    override func setUpWithError() throws {
        do {
            try PrayerWidgetStore.save(snapshot)
            try PrayerWidgetStore.save(nil)
        } catch let failure as PrayerWidgetStore.Failure where failure.status == errSecMissingEntitlement {
            throw XCTSkip("The keychain refuses this test host (\(failure.status)).")
        }
    }

    override func tearDown() {
        try? PrayerWidgetStore.save(nil)
        super.tearDown()
    }

    func testTheStoreKeepsReplacesAndDeletesTheTimes() throws {
        XCTAssertNil(PrayerWidgetStore.load())
        try PrayerWidgetStore.save(snapshot)
        XCTAssertEqual(PrayerWidgetStore.load(), snapshot)
        let later = PrayerWidgetSnapshot(zone: "Asia/Riyadh", prayers: [])
        try PrayerWidgetStore.save(later)
        XCTAssertEqual(PrayerWidgetStore.load(), later)
        try PrayerWidgetStore.save(nil)
        XCTAssertNil(PrayerWidgetStore.load())
        try PrayerWidgetStore.save(nil)
    }

    /// «حذف كل البيانات» deletes an item `load()` cannot read, such as another format's.
    @MainActor
    func testPublishingNothingDeletesAnUnreadableItem() throws {
        let other = try XCTUnwrap(String(data: try snapshot.encoded(), encoding: .utf8))
            .replacingOccurrences(of: #""format":1"#, with: #""format":2"#)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "athkar.prayer-widget",
                                   kSecAttrAccount as String: "snapshot"]
        XCTAssertEqual(SecItemAdd(item.merging([kSecValueData as String: Data(other.utf8)]) { $1 } as CFDictionary,
                                  nil), errSecSuccess)
        XCTAssertNil(PrayerWidgetStore.load())

        KeychainPrayerWidget().publish(nil)
        XCTAssertEqual(SecItemCopyMatching(item as CFDictionary, nil), errSecItemNotFound)
    }
}
