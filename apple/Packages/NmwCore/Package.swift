// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NmwCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NmwCore", targets: ["NmwCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NmwCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "NmwCoreTests", dependencies: ["NmwCore"]),
    ]
)
