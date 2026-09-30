// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ClickportCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ClickportCore", targets: ["ClickportCore"])],
    targets: [
        .target(name: "ClickportCore", resources: [.process("Resources")]),
        .testTarget(name: "ClickportCoreTests", dependencies: ["ClickportCore"])
    ]
)
