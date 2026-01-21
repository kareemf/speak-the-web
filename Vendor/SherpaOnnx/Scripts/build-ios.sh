#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"
SRC_DIR="$BUILD_DIR/sherpa-onnx"
ARTIFACTS_DIR="$ROOT_DIR/Artifacts"

mkdir -p "$BUILD_DIR" "$ARTIFACTS_DIR"

if [ ! -d "$SRC_DIR" ]; then
  git clone --depth 1 https://github.com/k2-fsa/sherpa-onnx.git "$SRC_DIR"
fi

pushd "$SRC_DIR" > /dev/null

bash build-ios.sh

rm -rf "$ARTIFACTS_DIR/sherpa-onnx.xcframework" "$ARTIFACTS_DIR/onnxruntime.xcframework"

ditto build-ios/sherpa-onnx.xcframework "$ARTIFACTS_DIR/sherpa-onnx.xcframework"

ONNX_FRAMEWORK_PATH=$(find build-ios/ios-onnxruntime -name onnxruntime.xcframework -type d -print -quit)
if [ -z "${ONNX_FRAMEWORK_PATH}" ]; then
  echo "onnxruntime.xcframework not found in build-ios/ios-onnxruntime" >&2
  exit 1
fi
ditto "$ONNX_FRAMEWORK_PATH" "$ARTIFACTS_DIR/onnxruntime.xcframework"

popd > /dev/null

echo "Copied xcframeworks to $ARTIFACTS_DIR"
