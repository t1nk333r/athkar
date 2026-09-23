// swift-tools-version: 6.0
// Domain layer: no UIKit/SwiftUI/CoreLocation/UserNotifications (NATIVE_APP_PLAN.md 9).
import PackageDescription

let package = Package(
    name: "AthkarCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AthkarCore", targets: ["AthkarCore"])],
    targets: [
        .target(name: "AthkarCore"),
        .testTarget(name: "AthkarCoreTests", dependencies: ["AthkarCore"]),
    ]
)
