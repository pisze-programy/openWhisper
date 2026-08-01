// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OpenWhisperShared",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "OpenWhisperShared", targets: ["OpenWhisperShared"])
    ],
    targets: [
        .target(name: "OpenWhisperShared")
    ]
)
