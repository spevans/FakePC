// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FakePC",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(url: "https://github.com/spevans/hypervisor-kit", from: "0.0.1"),
        .package(url: "https://github.com/spevans/swift-babab.git", from: "0.0.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.3.0")),
    ],
    targets: [
        .target(
            name: "FakePC",
            dependencies: [
                "CFakePC",
                .product(name: "HypervisorKit", package: "hypervisor-kit"),
                .product(name: "BABAB", package: "swift-babab"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["bios"],
            resources: [.process("Resources")]
        ),
        .target(name: "CFakePC", dependencies: []),
        .testTarget(name: "FakePCTests", dependencies: ["FakePC"]),
    ]
)
