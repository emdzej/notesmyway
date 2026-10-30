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
        .package(path: "../NmwShared"),
        .package(path: "../../../../markdownkit"),
    ],
    targets: [
        .target(
            name: "NmwUI",
            dependencies: [
                "NmwCore",
                "NmwShared",
                .product(name: "MarkdownEngine", package: "markdownkit"),
                .product(name: "MarkdownEngineCodeBlocks", package: "markdownkit"),
                .product(name: "MarkdownEngineLatex", package: "markdownkit"),
            ]
        ),
        .testTarget(name: "NmwUITests", dependencies: ["NmwUI"]),
    ]
)
