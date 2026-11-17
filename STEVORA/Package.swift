// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StevoraCore",
    platforms: [.iOS(.v16)],
    products: [.library(name: "StevoraCore", targets: ["StevoraCore"])],
    targets: [
        .target(name: "StevoraCore"),
        .testTarget(name: "StevoraCoreTests", dependencies: ["StevoraCore"])
    ]
)
