// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FilmCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FilmCore", targets: ["FilmCore"]),
        .library(name: "FilmScript", targets: ["FilmScript"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "FilmScript",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(
            name: "FilmCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "FilmScript",
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
