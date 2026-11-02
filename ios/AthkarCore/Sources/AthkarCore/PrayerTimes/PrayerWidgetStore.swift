#if canImport(Security)
import Foundation
import Security

/// Where the app leaves ``PrayerWidgetSnapshot`` for the widget extension: one generic-password keychain item in the
/// default access group. An App Group would need a provisioning profile that names the group, and the wildcard
/// profiles Feather signs with cannot; Feather gives the extension the app's own entitlements instead, so both read
/// the same default group. A build signed per target (NATIVE_APP_PLAN.md §8.1) needs a shared
/// `keychain-access-groups` entry for both.
///
/// The item is readable after the first unlock, so a locked phone's widget can read it, and never leaves the device:
/// it is not synchronized or restored to another phone.
public enum PrayerWidgetStore {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "athkar.prayer-widget",
         kSecAttrAccount as String: "snapshot"]
    }

    /// `nil` when there is no snapshot, the keychain refuses, or the item holds another format.
    public static func load() -> PrayerWidgetSnapshot? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return PrayerWidgetSnapshot.decoded(from: data)
    }

    /// Replaces the snapshot; `nil` deletes it.
    public static func save(_ snapshot: PrayerWidgetSnapshot?) throws {
        guard let snapshot else {
            let status = SecItemDelete(item as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }
        let values: [String: Any] = [
            kSecValueData as String: try snapshot.encoded(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(item as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging(values) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
#endif
