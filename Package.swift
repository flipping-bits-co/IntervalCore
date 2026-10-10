// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IntervalCore",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "IntervalCore", targets: ["IntervalCore"]),
    ],
    targets: [
        .target(name: "IntervalCore"),
        .testTarget(name: "IntervalCoreTests", dependencies: ["IntervalCore"]),
    ],
    swiftLanguageModes: [.v6]
)
