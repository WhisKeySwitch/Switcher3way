// swift-tools-version: 6.0
import PackageDescription

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
