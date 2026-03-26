// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeLight",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .executableTarget(
            name: "VibeLight",
            dependencies: ["CLibProc"],
            path: "Sources/VibeLight",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "VibeLightTests",
            dependencies: ["VibeLight"],
            path: "Tests/VibeLightTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
