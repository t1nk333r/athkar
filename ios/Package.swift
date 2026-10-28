// swift-tools-version: 6.2
import Foundation
import PackageDescription

// SDK mode is compile-only. The runner populates Resources in its isolated source snapshot.
let sdkBuild = ProcessInfo.processInfo.environment["ATHKAR_LINUX_SDK_BUILD"] == "1"
let core: Target.Dependency = .product(name: "AthkarCore", package: "AthkarCore")
let crypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto")

let package = Package(
    name: "AthkarNativeVerification",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "AthkarCore"),
        // 5.0.1 requires Swift 6.2; the installed Linux toolchain is Swift 6.4.
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.1"),
    ],
    targets: sdkBuild ? [
        .executableTarget(
            name: "Athkar", dependencies: [core], path: "Athkar",
            exclude: ["Info.plist"],
            resources: [.copy("Assets.xcassets"), .process("Resources")]
        ),
        .testTarget(name: "AthkarTests", dependencies: ["Athkar", core], path: "AthkarTests"),
    ] : [
        .target(
            name: "AthkarModels", dependencies: [core, crypto], path: "Athkar",
            exclude: ["App/AppModel.swift", "Assets.xcassets", "AthkarApp.swift", "Deck/DeckCardView.swift",
                      "Deck/DeckIndexView.swift", "Deck/SectionChips.swift",
                      "Deck/DeckView.swift", "Design/Palette.swift", "Design/ReadingMetrics.swift",
                      "DeviceLocation.swift", "Info.plist", "Platform", "Prayer", "Qibla/DeviceHeading.swift",
                      "Qibla/QiblaView.swift", "Reminders/ReminderNotifications.swift", "Reminders/ReminderViews.swift",
                      "Screens"],
            sources: ["Deck/DeckModel.swift", "Deck/AdhkarDeckModel.swift", "Deck/RuqyahDeckModel.swift",
                      "Design/ArabicFormat.swift", "Content/BundledContent.swift", "App/TestHooks.swift",
                      "OneShotLocationRequest.swift", "App/SettingsModel.swift", "Qibla/HeadingReading.swift",
                      "Reminders/ReminderModel.swift", "App/DayRollover.swift"]
        ),
        .testTarget(name: "AthkarPortableTests", dependencies: ["AthkarModels", core, crypto],
                    path: "AthkarPortableTests"),
    ]
)
