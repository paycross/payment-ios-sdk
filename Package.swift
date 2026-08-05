// swift-tools-version: 6.0
import PackageDescription

// PayCrossCore is deliberately free of UIKit/SwiftUI/WebKit so it builds and tests
// on Linux. That is not an abstract nicety: the SDK is developed from WSL2 with no
// Apple hardware, so every behaviour that lives in Core is verifiable on every
// commit, and everything in PayCross is not.
let package = Package(
    name: "PayCross",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PayCross", targets: ["PayCross"]),
        .library(name: "PayCrossCore", targets: ["PayCrossCore"])
    ],
    targets: [
        .target(
            name: "PayCrossCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PayCross",
            dependencies: ["PayCrossCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PayCrossCoreTests",
            dependencies: ["PayCrossCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Renders the SwiftUI surfaces to PNGs on a macOS runner. Empty on Linux.
        .testTarget(
            name: "PayCrossUITests",
            dependencies: ["PayCross", "PayCrossCore", "DemoHarnessCore", "DemoHarnessUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The demo harness's logic: seeds, minting, deep links, outcome reading.
        // Platform-agnostic on purpose, so the automation contract is testable.
        .target(
            name: "DemoHarnessCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Harness screens. Lives in the package rather than only in an app target
        // so the screenshot pipeline can render it before an app exists.
        .target(
            name: "DemoHarnessUI",
            dependencies: ["DemoHarnessCore", "PayCross"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DemoHarnessCoreTests",
            dependencies: ["DemoHarnessCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
