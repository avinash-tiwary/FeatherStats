// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FeatherStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FeatherStats", targets: ["FeatherStats"])
    ],
    targets: [
        .executableTarget(
            name: "FeatherStats",
            dependencies: ["CSystemSensors"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "CSystemSensors",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "FeatherStatsTests",
            dependencies: ["FeatherStats"]
        )
    ]
)
