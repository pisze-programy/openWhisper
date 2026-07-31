// swift-tools-version:5.10
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────
// parakeet-coreml-ios — maintained fork of mweinbach/parakeet-coreml-swift.
//
// Performance note: the upstream build forces `-O` via `.unsafeFlags`, which
// Xcode refuses to link into an app target. This fork drops the forced flag:
// the library builds at the normal project optimization level — `-O` in
// Release (App Store), `-Onone` in Debug (≈40× real-time instead of ≈400×).
// See Changes.md for the full list of modifications.
// ─────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "ParakeetCoreMLiOS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "ParakeetTDT",
            targets: ["ParakeetTDT"]
        ),
        .executable(
            name: "parakeet",
            targets: ["ParakeetCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ParakeetTDT",
            path: "Sources/ParakeetTDT"
        ),
        .executableTarget(
            name: "ParakeetCLI",
            dependencies: [
                "ParakeetTDT",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ParakeetCLI"
        ),
        .testTarget(
            name: "ParakeetTDTTests",
            dependencies: ["ParakeetTDT"],
            path: "Tests/ParakeetTDTTests"
        ),
    ]
)
