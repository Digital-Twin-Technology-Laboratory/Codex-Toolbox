// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexToolbox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexToolboxCore", targets: ["CodexToolboxCore"]),
        .executable(name: "CoreVerification", targets: ["CoreVerification"])
    ],
    targets: [
        .target(
            name: "CodexToolboxCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "CoreVerification",
            dependencies: ["CodexToolboxCore"],
            path: "Verification/CoreVerification"
        ),
        .testTarget(
            name: "CodexToolboxTests",
            dependencies: ["CodexToolboxCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
