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
            path: "Artifacts/sherpa-onnx.xcframework"
        ),
        .binaryTarget(
            name: "OnnxRuntimeBinary",
            path: "Artifacts/onnxruntime.xcframework"
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
