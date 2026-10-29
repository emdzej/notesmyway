// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NmwUI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NmwUI", targets: ["NmwUI"]),
    ],
    dependencies: [
        .package(path: "../NmwCore"),
        .package(path: "../../../../swift-markdown-engine"),
    ],
    targets: [
        .target(
            name: "NmwUI",
            dependencies: [
                "NmwCore",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineCodeBlocks", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineLatex", package: "swift-markdown-engine"),
            ]
        ),
        .testTarget(name: "NmwUITests", dependencies: ["NmwUI"]),
    ]
)
