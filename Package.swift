// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glisse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Glisse", path: "Sources/Glisse")
    ]
)
