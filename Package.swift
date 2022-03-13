// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VERSETransitions",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "VERSETransitions",
            targets: [
                "VERSETransitions"
            ]
        ),
    ],
    dependencies: [
        .package(
            name: "verse",
            url: "https://github.com/Incetro/verse",
            branch: "master"
        ),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "VERSETransitions",
            dependencies: [
                .product(name: "VERSE", package: "verse"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        )
    ]
)
