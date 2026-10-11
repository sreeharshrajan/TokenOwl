// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TokenOwl",
    platforms: [
        // macOS 14 gives us MenuBarExtra (macOS 13+) and the Observation
        // framework's @Observable (macOS 14+) used by the menu-bar UI.
        .macOS(.v14)
    ],
    targets: [
        // Core domain, providers and services. No SwiftUI: everything here is
        // testable from `swift test` without a running application.
        .target(
            name: "TokenOwlCore",
            linkerSettings: [
                // Read-only access to the IDE's SQLite state database.
                .linkedLibrary("sqlite3")
            ]
        ),

        // Existing CLI POC diagnostics, kept useful on top of the core services.
        .executableTarget(
            name: "TokenOwl",
            dependencies: ["TokenOwlCore"]
        ),

        // Native macOS menu-bar application.
        .executableTarget(
            name: "TokenOwlApp",
            dependencies: ["TokenOwlCore"]
        ),

        .testTarget(
            name: "TokenOwlTests",
            dependencies: ["TokenOwlCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
