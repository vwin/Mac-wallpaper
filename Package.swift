// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumenWall",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumenWall", targets: ["LumenWall"])],
    targets: [
        .executableTarget(name: "LumenWall", resources: [.process("Resources")]),
        .testTarget(name: "LumenWallTests", dependencies: ["LumenWall"])
    ]
)
