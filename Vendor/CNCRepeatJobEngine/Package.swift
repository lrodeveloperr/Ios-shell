// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CNCRepeatJobEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CNCRepeatJobEngine", targets: ["CNCRepeatJobEngine"])],
    targets: [
        .target(name: "CNCRepeatJobEngine"),
        .testTarget(name: "CNCRepeatJobEngineTests", dependencies: ["CNCRepeatJobEngine"])
    ]
)
