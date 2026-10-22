// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RestoreGPSTime",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RestoreGPSTimeCore", targets: ["RestoreGPSTimeCore"]),
        .executable(name: "RestoreGPSTime", targets: ["RestoreGPSTime"])
    ],
    targets: [
        .target(name: "RestoreGPSTimeCore"),
        .executableTarget(name: "RestoreGPSTime", dependencies: ["RestoreGPSTimeCore"]),
        .testTarget(name: "RestoreGPSTimeCoreTests", dependencies: ["RestoreGPSTimeCore"])
    ],
    swiftLanguageVersions: [.v5]
)
