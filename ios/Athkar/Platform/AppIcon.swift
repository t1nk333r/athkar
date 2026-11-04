import UIKit

/// The home-screen icon, chosen in الإعدادات › «أيقونة التطبيق» (tools/app-icons.py draws both). The letter ب is the
/// primary icon, and each choice is an alternate icon set (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in
/// ios/project.yml): «الباء» is a copy of the primary icon. iOS keeps the choice, not the settings table, and shows
/// its own alert when the icon changes. Each icon has light, dark and tinted versions, which iOS 18 picks from the
/// home screen's appearance.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case letter
    case horizon

    var id: Self { self }

    /// The icon set's name for `setAlternateIconName`. Never nil: from iOS 26.1, and still on 26.6,
    /// `setAlternateIconName(nil)` can leave the alternate icon on the home screen
    /// (https://developer.apple.com/forums/thread/809474). Naming the primary icon instead can stop the call working
    /// until the phone restarts, so «الباء» is its own alternate copy.
    var alternateIconName: String {
        switch self {
        case .letter: "AppIconLetter"
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

    /// The preview's bitmap in the app's light or dark colours. A bitmap and not an asset image: SwiftUI resolves an
    /// asset image again in the sheet's own colour scheme, which stays light when the theme turns dark with الإعدادات
    /// open.
    @MainActor func previewImage(dark: Bool) -> CGImage? {
        UIImage(named: preview, in: nil, compatibleWith: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))?
            .cgImage
    }

    /// No name is the primary icon, the letter. An unknown name, such as one a later version removed, reads as the
    /// primary icon too.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .letter
    }

    @MainActor static var current: AppIconChoice {
        AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
    }

    @MainActor static var isAvailable: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Whether iOS reports this choice's own icon set. The letter can show as current without it: on the primary icon,
    /// or after `setAlternateIconName(nil)` failed to restore it, so a tap still switches to its copy.
    @MainActor var isApplied: Bool { UIApplication.shared.alternateIconName == alternateIconName }

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
