// swift-tools-version: 5.9
//
//  Package.swift — WhisperType
//
//  WhisperType is built with Swift Package Manager. Transcription is performed
//  in-process by WhisperKit (CoreML / Apple Neural Engine); the Whisper model is
//  downloaded on demand on first use and cached, so nothing is bundled and there
//  is no whisper.cpp subprocess.
//
//  `swift build` produces a bare executable; `scripts/build-app.sh` wraps it in a
//  signed `WhisperType.app` bundle (see that script and README.md).
//
import PackageDescription

let package = Package(
    name: "WhisperType",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        // WhisperKit ships as the "argmax-oss-swift" package; we only need the
        // WhisperKit product. Models are fetched lazily from Hugging Face.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperType",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "src"
        ),
    ]
)
