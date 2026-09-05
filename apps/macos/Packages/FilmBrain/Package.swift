// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FilmBrain",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FilmBrain", targets: ["FilmBrain"]),
    ],
    dependencies: [
        .package(path: "../FilmCore"),
        .package(url: "https://github.com/ajevans99/swift-json-schema.git", exact: "0.13.1"),
    ],
    targets: [
        .target(
            name: "FilmBrain",
            dependencies: [
                "FilmCore",
                .product(name: "JSONSchema", package: "swift-json-schema"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
