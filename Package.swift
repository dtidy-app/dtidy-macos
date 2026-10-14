// swift-tools-version: 6.0
//
// dtidy - sort loose items on the macOS Desktop, with undo.
// Copyright (C) 2026 dtidy contributors. Licensed under GPL-3.0-or-later.

import PackageDescription

let package = Package(
    name: "dtidy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "dtidy", targets: ["dtidy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
    targets: [
        .target(name: "DTidyCore"),
        .target(name: "DTidyIO", dependencies: ["DTidyCore"]),
        .executableTarget(
            name: "dtidy",
            dependencies: [
                "DTidyCore",
                "DTidyIO",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "DTidyCoreTests", dependencies: ["DTidyCore"]),
        .testTarget(name: "DTidyIOTests", dependencies: ["DTidyCore", "DTidyIO"]),
        .testTarget(
            name: "DTidyCLITests",
            dependencies: ["dtidy", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
