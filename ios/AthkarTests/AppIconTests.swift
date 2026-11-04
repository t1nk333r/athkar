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

    /// The dark preview is the dark bitmap: its tile is ink where the light one's is paper.
    @MainActor
    func testPreviewBitmapFollowsTheScheme() throws {
        for choice in AppIconChoice.allCases {
            let light = try XCTUnwrap(choice.previewImage(dark: false), choice.preview)
            let dark = try XCTUnwrap(choice.previewImage(dark: true), choice.preview)
            XCTAssertGreaterThan(try cornerBrightness(light), 0.8, choice.preview)
            XCTAssertLessThan(try cornerBrightness(dark), 0.3, choice.preview)
        }
    }

    /// The brightness, 0 to 1, of the pixel 8 pixels in from the top-left corner, inside the tile.
    private func cornerBrightness(_ image: CGImage) throws -> Double {
        let corner = try XCTUnwrap(image.cropping(to: CGRect(x: 8, y: 8, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drawn, "no bitmap context")
        return Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
    }
}
