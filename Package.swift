// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleAudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SimpleAudioCore", targets: ["SimpleAudioCore"]),
        .library(name: "SimpleAudioEngine", targets: ["SimpleAudioEngine"]),
        .executable(name: "SimpleAudio", targets: ["SimpleAudio"]),
        .executable(name: "simpleaudio-mcp", targets: ["simpleaudio-mcp"]),
    ],
    targets: [
        .target(name: "SimpleAudioCore"),
        .target(name: "SimpleAudioEngine", dependencies: ["SimpleAudioCore"]),
        .executableTarget(name: "SimpleAudio", dependencies: ["SimpleAudioCore", "SimpleAudioEngine"]),
        .target(name: "SimpleAudioMCPCore"),
        .executableTarget(name: "simpleaudio-mcp", dependencies: ["SimpleAudioMCPCore"]),
        .testTarget(name: "SimpleAudioCoreTests", dependencies: ["SimpleAudioCore"]),
        .testTarget(name: "SimpleAudioEngineTests", dependencies: ["SimpleAudioCore", "SimpleAudioEngine"]),
        .testTarget(name: "SimpleAudioMCPTests", dependencies: ["SimpleAudioMCPCore"]),
        .testTarget(name: "SimpleAudioAppTests", dependencies: ["SimpleAudio", "SimpleAudioCore", "SimpleAudioEngine"]),
    ],
    swiftLanguageModes: [.v5]
)
