// swift-tools-version: 6.0
//
// dsort - sort loose items on the macOS Desktop, with undo.
// Copyright (C) 2026 dsort contributors. Licensed under GPL-3.0-or-later.

import PackageDescription

let package = Package(
    name: "dsort",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "dsort", targets: ["dsort"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
    targets: [
        .target(name: "DSortCore"),
        .target(name: "DSortIO", dependencies: ["DSortCore"]),
        .executableTarget(
            name: "dsort",
            dependencies: [
                "DSortCore",
                "DSortIO",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "DSortCoreTests", dependencies: ["DSortCore"]),
        .testTarget(name: "DSortIOTests", dependencies: ["DSortCore", "DSortIO"]),
    ],
    swiftLanguageModes: [.v6]
)
