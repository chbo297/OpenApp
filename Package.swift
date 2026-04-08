// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenAPP",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "OpenAPP",
            targets: ["OpenAPP"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenAPP",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "OpenAPPTests",
            dependencies: ["OpenAPP"],
            path: "Tests"
        ),
    ]
)
