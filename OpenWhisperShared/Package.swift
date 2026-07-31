// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OpenWhisperShared",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "OpenWhisperShared", targets: ["OpenWhisperShared"])
    ],
    dependencies: [
        .package(path: "../Packages/parakeet-coreml-swift")
    ],
    targets: [
        .target(
            name: "OpenWhisperShared",
            dependencies: [
                .product(name: "ParakeetTDT", package: "parakeet-coreml-swift")
            ]
        )
    ]
)
