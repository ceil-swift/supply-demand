// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "SupplyDemand",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "SupplyDemand",
            targets: ["SupplyDemand"])
    ],
    targets: [
        .target(
            name: "SupplyDemand"),
        .testTarget(
            name: "SupplyDemandTests",
            dependencies: ["SupplyDemand"]
        ),
    ]
)
