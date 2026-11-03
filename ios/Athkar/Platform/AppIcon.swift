import UIKit

/// The home-screen icon, chosen in الإعدادات › «أيقونة التطبيق» (tools/app-icons.py draws both). The letter ب is the
/// primary icon; the horizon is an alternate icon set (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in
/// ios/project.yml). iOS keeps the choice, not the settings table, and shows its own alert when the icon changes.
/// Each icon has light, dark and tinted versions, which iOS 18 picks from the home screen's appearance.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case letter
    case horizon

    var id: Self { self }

    /// The icon set's name for `setAlternateIconName`, nil for the primary icon.
    var alternateIconName: String? {
        switch self {
        case .letter: nil
        case .horizon: "AppIconHorizon"
        }
    }

    var title: String {
        switch self {
        case .letter: "الباء"
        case .horizon: "الأفق"
        }
    }

    /// The image set that shows this icon in الإعدادات, in the app's light or dark colours.
    var preview: String {
        switch self {
        case .letter: "IconChoiceLetter"
        case .horizon: "IconChoiceHorizon"
        }
    }

    /// An unknown name, such as one a later version removed, reads as the primary icon.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .letter
    }

    @MainActor static var current: AppIconChoice {
        AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
    }

    @MainActor static var isAvailable: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Returns whether iOS changed the icon.
    @MainActor func apply() async -> Bool {
        do {
            try await UIApplication.shared.setAlternateIconName(alternateIconName)
            return true
        } catch {
            return false
        }
    }
}
