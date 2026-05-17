// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "apple-vision-ocr-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppleVisionOCRCore", targets: ["AppleVisionOCRCore"]),
        .executable(name: "apple-vision-ocr", targets: ["AppleVisionOCRCLI"]),
        .executable(name: "VOCR", targets: ["VOCR"])
    ],
    targets: [
        .target(name: "AppleVisionOCRCore"),
        .executableTarget(
            name: "AppleVisionOCRCLI",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .executableTarget(
            name: "VOCR",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .testTarget(
            name: "AppleVisionOCRCoreTests",
            dependencies: ["AppleVisionOCRCore"]
        ),
        .testTarget(
            name: "AppleVisionOCRCLITests",
            dependencies: ["AppleVisionOCRCLI", "AppleVisionOCRCore"]
        ),
        .testTarget(
            name: "VOCRTests",
            dependencies: ["VOCR"]
        )
    ]
)
