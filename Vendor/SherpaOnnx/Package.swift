// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SherpaOnnx",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SherpaOnnx", targets: ["SherpaOnnx"])
    ],
    targets: [
        .binaryTarget(
            name: "SherpaOnnxBinary",
            url: "https://github.com/kareemf/speak-the-web/releases/download/sherpa-v1.0.0/sherpa-onnx.xcframework.zip",
            checksum: "bf7dadb28cf7361ddc0d297de120e098f9d8665d3ceb39b8f16e827601675d60"
        ),
        .binaryTarget(
            name: "OnnxRuntimeBinary",
            url: "https://github.com/kareemf/speak-the-web/releases/download/sherpa-v1.0.0/onnxruntime.xcframework.zip",
            checksum: "962d2acd2729504830806fdea36ebe1658869811f35842013745dfa7781ca75a"
        ),
        .target(
            name: "SherpaOnnxC",
            dependencies: ["SherpaOnnxBinary", "OnnxRuntimeBinary"],
            path: "Sources/SherpaOnnxC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SherpaOnnx",
            dependencies: ["SherpaOnnxC"],
            path: "Sources/SherpaOnnx"
        )
    ]
)
