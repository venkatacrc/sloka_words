// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SlokaWords",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SlokaWords",
            resources: [.copy("Resources/words.json")]
        )
    ]
)
