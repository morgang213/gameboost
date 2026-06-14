// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GameBoost",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GameBoost",
            path: "Sources/GameBoost"
        )
    ]
)
