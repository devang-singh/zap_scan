// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zap_scan",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "zap-scan", targets: ["zap_scan"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "zap_scan",
            dependencies: [],
            path: "apple", // We will move shared code here
            resources: [
                .process("Resources")
            ]
        )
    ]
)
