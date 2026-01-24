# SPM Remote Binary Targets for SherpaOnnx

**Status**: Implemented
**Date**: 2026-01-23

## Problem

The prebuilt xcframeworks (`sherpa-onnx.xcframework`, `onnxruntime.xcframework`) are gitignored and not tracked in the repository. This means:

1. **CI/CD (Xcode Cloud)** cannot build without first running `build-ios.sh`
2. **New contributors** must run the build script before building the project
3. **Build times** are long if compiling from source on every CI run

## Current State

```swift
// Vendor/SherpaOnnx/Package.swift (current)
.binaryTarget(
    name: "SherpaOnnxBinary",
    path: "Artifacts/sherpa-onnx.xcframework"  // Local path - gitignored
),
.binaryTarget(
    name: "OnnxRuntimeBinary",
    path: "Artifacts/onnxruntime.xcframework"  // Local path - gitignored
),
```

**Dependency chain**:
```
SherpaOnnx (Swift)
  └── SherpaOnnxC (C headers)
        ├── SherpaOnnxBinary (xcframework)
        └── OnnxRuntimeBinary (xcframework)
```

## Target State

Host xcframeworks on GitHub Releases and reference them via URL:

```swift
// Vendor/SherpaOnnx/Package.swift (target)
.binaryTarget(
    name: "SherpaOnnxBinary",
    url: "https://github.com/user/speak-the-web/releases/download/sherpa-v1.0.0/sherpa-onnx.xcframework.zip",
    checksum: "abc123..."
),
.binaryTarget(
    name: "OnnxRuntimeBinary",
    url: "https://github.com/user/speak-the-web/releases/download/sherpa-v1.0.0/onnxruntime.xcframework.zip",
    checksum: "def456..."
),
```

## Benefits

| Aspect | Before (Local) | After (Remote) |
|--------|----------------|----------------|
| CI/CD | Must run build-ios.sh | SPM resolves automatically |
| New contributor | Must run build script | Just clone and build |
| Caching | None | SPM caches resolved packages |
| Versioning | Implicit (whatever is built) | Explicit (checksum + release tag) |

---

## Implementation Plan

### Phase 1: Prepare Artifacts

#### 1.1 Build xcframeworks locally
```bash
./Vendor/SherpaOnnx/Scripts/build-ios.sh
```

#### 1.2 Zip each xcframework
SPM requires `.zip` format for remote binary targets.

```bash
cd Vendor/SherpaOnnx/Artifacts

# Zip each framework (must be at root of zip, not nested)
zip -r sherpa-onnx.xcframework.zip sherpa-onnx.xcframework
zip -r onnxruntime.xcframework.zip onnxruntime.xcframework
```

#### 1.3 Compute checksums
SPM uses SHA-256 checksums for integrity verification.

```bash
swift package compute-checksum sherpa-onnx.xcframework.zip
swift package compute-checksum onnxruntime.xcframework.zip
```

Save these checksums for the Package.swift update.

---

### Phase 2: Host Artifacts

#### 2.1 Create a GitHub Release

Option A: **Same repository** (simpler)
```bash
gh release create sherpa-v1.0.0 \
  --title "SherpaOnnx Binaries v1.0.0" \
  --notes "Prebuilt xcframeworks for iOS" \
  Vendor/SherpaOnnx/Artifacts/sherpa-onnx.xcframework.zip \
  Vendor/SherpaOnnx/Artifacts/onnxruntime.xcframework.zip
```

Option B: **Separate repository** (if binaries are large or shared across projects)
- Create a dedicated `sherpa-onnx-ios-binaries` repo
- Upload zips as release assets there

#### 2.2 Verify download URLs
After creating the release, verify the asset URLs:
```
https://github.com/kareemf/speak-the-web/releases/download/sherpa-v1.0.0/sherpa-onnx.xcframework.zip
https://github.com/kareemf/speak-the-web/releases/download/sherpa-v1.0.0/onnxruntime.xcframework.zip
```

---

### Phase 3: Update Package.swift

#### 3.1 Modify binary targets

```swift
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
```

#### 3.2 Test locally
```bash
# Clear SPM cache to force re-download
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build

# Resolve and build
swift package resolve
swift build
```

---

### Phase 4: CI/CD Verification

#### 4.1 Xcode Cloud
No `ci_post_clone.sh` script needed. Xcode Cloud will:
1. Clone the repo
2. Resolve SPM dependencies (downloading xcframeworks from GitHub Releases)
3. Build the project

#### 4.2 Test a clean CI build
Push to a branch and verify Xcode Cloud builds successfully without the local Artifacts directory.

---

## Maintenance Workflow

When updating sherpa-onnx to a new version:

1. **Rebuild locally**
   ```bash
   ./Vendor/SherpaOnnx/Scripts/build-ios.sh
   ```

2. **Repackage and compute checksums**
   ```bash
   cd Vendor/SherpaOnnx/Artifacts
   zip -r sherpa-onnx.xcframework.zip sherpa-onnx.xcframework
   zip -r onnxruntime.xcframework.zip onnxruntime.xcframework
   swift package compute-checksum sherpa-onnx.xcframework.zip
   swift package compute-checksum onnxruntime.xcframework.zip
   ```

3. **Create new release**
   ```bash
   gh release create sherpa-v1.1.0 \
     --title "SherpaOnnx Binaries v1.1.0" \
     --notes "Updated to sherpa-onnx version X.Y.Z" \
     sherpa-onnx.xcframework.zip \
     onnxruntime.xcframework.zip
   ```

4. **Update Package.swift** with new URL and checksums

5. **Commit and push**

---

## Optional: Local Development Override

For local development/iteration without re-uploading, you can temporarily switch back to path-based targets:

```swift
#if LOCALDEV
.binaryTarget(name: "SherpaOnnxBinary", path: "Artifacts/sherpa-onnx.xcframework")
#else
.binaryTarget(name: "SherpaOnnxBinary", url: "...", checksum: "...")
#endif
```

However, this adds complexity. Recommended approach: just use remote targets consistently.

---

## Out of Scope

- Automating the release creation (could be a GitHub Action in the future)
- Supporting macOS/visionOS targets (currently iOS only)
- Swift Package Registry (not yet widely adopted)

---

## TODOs

- [x] Build xcframeworks locally
- [x] Zip and compute checksums
- [x] Create GitHub Release with artifacts
- [x] Update Package.swift with URLs and checksums
- [x] Test SPM resolution locally
- [ ] Verify Xcode Cloud build succeeds
- [ ] Document sherpa-onnx upstream version in release notes
