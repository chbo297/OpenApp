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
    dependencies: [
        .package(
            url: "https://github.com/chbo297/BODragScroll.git",
            from: "1.0.1"
        )
    ],
    targets: [
        .target(
            name: "OpenAPP",
            dependencies: [
                .product(
                    name: "BODragScroll",
                    package: "BODragScroll",
                    condition: .when(platforms: [.iOS, .macCatalyst])
                )
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "OpenAPPTests",
            dependencies: ["OpenAPP"],
            path: "Tests"
        ),
    ]
)
