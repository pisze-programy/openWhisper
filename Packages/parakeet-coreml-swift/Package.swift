// swift-tools-version:5.10
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────
// VENDORED COPY — OpenWhisper
//
// This package is vendored from upstream https://github.com/mweinbach/
// parakeet-coreml-swift @ 0.1.1 because Xcode refuses to link packages
// that use `.unsafeFlags` into an app target ("uses unsafe build flags").
// The only change vs. upstream is the removal of the forced `-O` flag
// below. Keep this file otherwise identical to upstream to make future
// syncs trivial.
//
// Performance note: without the forced `-O`, the library builds at the
// normal project optimization level — `-O` in Release (App Store), and
// `-Onone` in Debug, which makes Debug transcription slower but still
// usable (≈40× real-time factor instead of ≈400×).
// ─────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "ParakeetCoreML",
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
