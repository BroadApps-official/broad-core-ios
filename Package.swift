// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BroadCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BroadCore", targets: ["BroadCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Swinject/Swinject.git",
            exact: "2.10.0"
        )
    ],
    targets: [
        .target(name: "BroadCore",
            dependencies: [
                .product(name: "Swinject", package: "Swinject")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
