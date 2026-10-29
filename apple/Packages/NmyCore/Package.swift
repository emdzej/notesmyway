// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NmyCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NmyCore", targets: ["NmyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NmyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "NmyCoreTests", dependencies: ["NmyCore"]),
    ]
)
