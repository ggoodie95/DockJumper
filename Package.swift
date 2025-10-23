// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "DockJumper",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "DockJumper",
            targets: ["DockJumper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DockJumper",
            resources: [
                .process("Assets")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"], .when(configuration: .debug)),
                .unsafeFlags(["-parse-as-library"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SpriteKit")
            ]
        )
    ]
)
