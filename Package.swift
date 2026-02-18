// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sideman",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SidemanApp", targets: ["SidemanApp"])
    ],
    targets: [
        .executableTarget(
            name: "SidemanApp",
            path: "Sources/SidemanApp",
            exclude: ["Credits/README.md", "Spotify/README.md", "Playlist/README.md"]
        ),
        .testTarget(
            name: "SidemanAppTests",
            dependencies: ["SidemanApp"],
            path: "Tests/SidemanAppTests"
        )
    ]
)
