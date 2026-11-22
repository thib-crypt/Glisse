// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glisse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Glisse",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Glisse",
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
