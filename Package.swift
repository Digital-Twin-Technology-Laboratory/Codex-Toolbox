// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShowCodexIQ",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ShowCodexIQCore", targets: ["ShowCodexIQCore"]),
        .executable(name: "CoreVerification", targets: ["CoreVerification"])
    ],
    targets: [
        .target(name: "ShowCodexIQCore"),
        .executableTarget(
            name: "CoreVerification",
            dependencies: ["ShowCodexIQCore"],
            path: "Verification/CoreVerification"
        ),
        .testTarget(
            name: "ShowCodexIQTests",
            dependencies: ["ShowCodexIQCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
