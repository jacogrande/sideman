// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "spofty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpoftyApp", targets: ["SpoftyApp"])
    ],
    targets: [
        .executableTarget(
            name: "SpoftyApp",
            path: "Sources/SpoftyApp"
        ),
        .testTarget(
            name: "SpoftyAppTests",
            dependencies: ["SpoftyApp"],
            path: "Tests/SpoftyAppTests"
        )
    ]
)
