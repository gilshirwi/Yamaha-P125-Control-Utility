// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "P125Control",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "P125Control", targets: ["P125Control"]),
        .executable(name: "P125LoginLauncher", targets: ["P125LoginLauncher"]),
        .executable(name: "p125", targets: ["P125CLI"])
    ],
    targets: [
        .target(name: "P125Core"),
        .executableTarget(name: "P125Control", dependencies: ["P125Core"]),
        .executableTarget(name: "P125LoginLauncher"),
        .executableTarget(name: "P125CLI", dependencies: ["P125Core"]),
        .testTarget(name: "P125CoreTests", dependencies: ["P125Core"])
    ]
)
