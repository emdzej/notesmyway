// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NmyUI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NmyUI", targets: ["NmyUI"]),
    ],
    dependencies: [
        .package(path: "../NmyCore"),
        .package(path: "../../../../swift-markdown-engine"),
    ],
    targets: [
        .target(
            name: "NmyUI",
            dependencies: [
                "NmyCore",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineCodeBlocks", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineLatex", package: "swift-markdown-engine"),
            ]
        ),
        .testTarget(name: "NmyUITests", dependencies: ["NmyUI"]),
    ]
)
