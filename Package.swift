// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flare",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .executableTarget(
            name: "Flare",
            dependencies: ["CLibProc"],
            path: "Sources/VibeLight",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "FlareTests",
            dependencies: ["Flare"],
            path: "Tests/VibeLightTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
