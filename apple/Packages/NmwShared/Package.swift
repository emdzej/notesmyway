// swift-tools-version: 6.2
import PackageDescription

// What the app and its extensions (widgets, share) exchange through the
// App Group container: the widget snapshot, share jobs, and app links.
// No dependencies, so the extensions stay small.
let package = Package(
    name: "NmwShared",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NmwShared", targets: ["NmwShared"]),
    ],
    targets: [
        .target(name: "NmwShared"),
        .testTarget(name: "NmwSharedTests", dependencies: ["NmwShared"]),
    ]
)
