// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CCusagebar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CCusagebar", targets: ["CCusagebar"])
    ],
    targets: [
        .executableTarget(
            name: "CCusagebar",
            path: "Sources/CCusagebar",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CCusagebarTests",
            dependencies: ["CCusagebar"],
            path: "Tests/CCusagebarTests"
        )
    ]
)
