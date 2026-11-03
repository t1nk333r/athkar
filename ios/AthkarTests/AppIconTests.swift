import UIKit
import XCTest
@testable import Athkar

/// «أيقونة التطبيق»: the build lists every choice's icon set, and each choice has its preview.
final class AppIconTests: XCTestCase {
    /// Xcode writes the icon keys into Info.plist from ios/project.yml's icon settings; a choice whose alternate icon
    /// set is missing would fail only when someone picks it.
    func testInfoPlistDeclaresEveryChoice() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: [String: Any]])
        XCTAssertEqual(Set(alternates.keys), Set(AppIconChoice.allCases.compactMap(\.alternateIconName)))
        for (name, entry) in alternates {
            XCTAssertEqual(entry["CFBundleIconName"] as? String, name)
        }
    }

    @MainActor
    func testChoicesRoundTripAndHavePreviews() {
        XCTAssertTrue(AppIconChoice.isAvailable)
        for choice in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateIconName: choice.alternateIconName), choice)
            XCTAssertNotNil(UIImage(named: choice.preview), choice.preview)
        }
        XCTAssertEqual(AppIconChoice(alternateIconName: "AppIconRemoved"), .letter)
    }
}
