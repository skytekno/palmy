// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PalmyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PalmyCore", targets: ["PalmyCore"])],
    targets: [.target(name: "PalmyCore"), .testTarget(name: "PalmyCoreTests", dependencies: ["PalmyCore"]) ]
)
