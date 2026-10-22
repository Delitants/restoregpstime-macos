// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RestoreGPSTime",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RestoreGPSTimeCore", targets: ["RestoreGPSTimeCore"]),
        .executable(name: "RestoreGPSTime", targets: ["RestoreGPSTime"]),
        .executable(name: "RestoreGPSTimeDroplet", targets: ["RestoreGPSTimeDroplet"]),
        .executable(name: "RestoreGPSTimeQA", targets: ["RestoreGPSTimeQA"])
    ],
    targets: [
        .target(name: "RestoreGPSTimeCore", resources:[.process("Resources")]),
        .executableTarget(name: "RestoreGPSTime", dependencies: ["RestoreGPSTimeCore"]),
        .executableTarget(name: "RestoreGPSTimeDroplet", dependencies: ["RestoreGPSTimeCore"]),
        .executableTarget(name: "RestoreGPSTimeQA", dependencies: ["RestoreGPSTimeCore"]),
        .testTarget(name: "RestoreGPSTimeQATests", dependencies: ["RestoreGPSTimeQA"]),
        .testTarget(name: "RestoreGPSTimeCoreTests", dependencies: ["RestoreGPSTimeCore"]),
        .testTarget(name: "RestoreGPSTimeAppTests", dependencies: ["RestoreGPSTime", "RestoreGPSTimeCore"])
    ],
    swiftLanguageVersions: [.v5]
)
