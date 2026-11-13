// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Two flavours from one source, selected by the environment:
//
//   swift build                      → direct build (unsandboxed, Developer ID, self-updating)
//   SWITCHER_APPSTORE=1 swift build  → App Store build (sandboxed, no updater)
//
// This mirrors the Windows port's `-p:Packaged=true`, for the same reason: a second target
// would duplicate the packaging and the two copies would drift.
//
// The condition is applied to the EXECUTABLE ONLY. Switcher3wCore must compile identically in
// both flavours — if detection could differ between them, a conversion correct in one build
// could be wrong in the other, and no test would catch it.
let appStoreFlavour = ProcessInfo.processInfo.environment["SWITCHER_APPSTORE"] == "1"
let executableSwiftSettings: [SwiftSetting] = appStoreFlavour ? [.define("SWITCHER_APPSTORE")] : []

let package = Package(
    name: "Switcher3w",
    platforms: [.macOS(.v13)],
    targets: [
        // The platform-independent decision logic: soft gates, N-way evaluation, phrase tracking.
        // Foundation only — no AppKit, no Carbon — so it is assertable without the app, its
        // permissions, or whichever layouts and dictionaries the machine happens to have.
        .target(
            name: "Switcher3wCore",
            path: "Sources/Switcher3wCore"
        ),
        .executableTarget(
            name: "Switcher3w",
            dependencies: ["Switcher3wCore"],
            path: "Sources/Switcher3w",
            swiftSettings: executableSwiftSettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "Switcher3wCoreTests",
            dependencies: ["Switcher3wCore"],
            path: "Tests/Switcher3wCoreTests"
        ),
    ]
)
