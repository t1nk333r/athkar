// swift-tools-version: 6.0
// Domain layer: no UIKit/SwiftUI/CoreLocation/UserNotifications (NATIVE_APP_PLAN.md 9).
import PackageDescription

let package = Package(
    name: "AthkarCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AthkarCore", targets: ["AthkarCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/batoulapps/adhan-swift.git", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AthkarCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Adhan", package: "adhan-swift"),
            ]
        ),
        .testTarget(
            name: "AthkarCoreTests",
            dependencies: ["AthkarCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
