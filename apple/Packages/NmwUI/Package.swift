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
        // Report a Problem: the ALIAS support desk's client and its report sheet.
        .package(url: "https://github.com/emdzej/alias-client-swift", from: "0.4.1"),
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
                .product(name: "AliasSupport", package: "alias-client-swift"),
                .product(name: "AliasSupportUI", package: "alias-client-swift"),
            ],
            resources: [.copy("Resources/Acknowledgements")]
        ),
        .testTarget(name: "NmwUITests", dependencies: ["NmwUI"]),
    ]
)
