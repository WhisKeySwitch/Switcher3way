// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switcher3w",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Switcher3w",
            path: "Sources/Switcher3w",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
