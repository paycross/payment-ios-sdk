// swift-tools-version: 6.0
import PackageDescription

// PayCrossCore imports no UIKit, SwiftUI or WebKit, so it builds and tests on Linux.
let package = Package(
    name: "PayCross",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PayCross", targets: ["PayCross"]),
        .library(name: "PayCrossCore", targets: ["PayCrossCore"])
    ],
    targets: [
        .target(
            name: "PayCrossCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PayCross",
            dependencies: ["PayCrossCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PayCrossCoreTests",
            dependencies: ["PayCrossCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Renders SwiftUI surfaces to PNGs on a macOS runner; empty on Linux.
        .testTarget(
            name: "PayCrossUITests",
            dependencies: ["PayCross", "PayCrossCore", "DemoHarnessCore", "DemoHarnessUI"],
            // Both lproj folders are needed: the French one proves an override beats the device language.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DemoHarnessCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DemoHarnessUI",
            dependencies: ["DemoHarnessCore", "PayCross", "PayCrossCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DemoHarnessCoreTests",
            dependencies: ["DemoHarnessCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
