// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Prospero",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/samalone/Plot.git", branch: "samalone/all-fixes"),
        .package(url: "https://github.com/samalone/plot-htmx.git", branch: "main"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-fluent.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/samalone/hummingbird-auth.git", branch: "csrf-middleware"),
    ],
    targets: [
        .executableTarget(
            name: "Prospero",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Plot", package: "Plot"),
                .product(name: "PlotHTMX", package: "plot-htmx"),
                .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdAuthViews", package: "hummingbird-auth"),
            ],
            resources: [
                .copy("Static"),
            ]
        ),
        .testTarget(
            name: "ProsperoTests",
            dependencies: ["Prospero"]
        ),
    ]
)
