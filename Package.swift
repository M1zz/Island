// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "IslandCore", targets: ["IslandCore"]),
        .executable(name: "island", targets: ["island"]),
        .executable(name: "island-sim", targets: ["island-sim"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "island", dependencies: ["IslandCore"]),
        .executableTarget(name: "island-sim", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
