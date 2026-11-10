// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lilt",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.4"),
    ],
    products: [
        .executable(
            name: "Lilt",
            targets: ["Lilt"]
        ),
        .executable(
            name: "api-explorer",
            targets: ["APIExplorer"]
        ),
    ],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Lilt",
            exclude: [
                "Resources/AppIcon.icon",
                "Resources/lilt.icns",
                // The checked-in .lproj files are the SwiftPM/Xcode 26 runtime
                // resources. build-app.sh compiles the source catalog for the
                // packaged app to avoid duplicate .strings outputs in SwiftPM.
                "Resources/Localizable.xcstrings",
                // App Shortcut phrases belong in the main bundle, which only
                // build-app.sh assembles; it compiles this catalog there.
                "Resources/AppShortcuts.xcstrings",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/ar.lproj"),
                .process("Resources/de.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/id.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/pl.lproj"),
                .process("Resources/pt.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/sv.lproj"),
                .process("Resources/tr.lproj"),
                .process("Resources/uk.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/Lilt.sdef"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // API Explorer CLI tool
        .executableTarget(
            name: "APIExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "APIExplorerTests",
            dependencies: ["APIExplorer"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Unit tests
        .testTarget(
            name: "LiltTests",
            dependencies: ["Lilt"],
            resources: [
                .process("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
