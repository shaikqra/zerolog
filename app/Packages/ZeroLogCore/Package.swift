// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeroLogCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "ZeroLogCore", targets: ["ZeroLogCore"]),
    ],
    targets: [
        .target(name: "ZeroLogCore", resources: [.process("Resources")]),
        .testTarget(name: "ZeroLogCoreTests", dependencies: ["ZeroLogCore"],
                    resources: [.process("Fixtures")]),
    ]
)
