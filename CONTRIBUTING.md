# Contributing to Speak the Web

Thank you for your interest in contributing to Speak the Web! This document provides guidelines for contributors.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) to maintain a welcoming community.

## Getting Started

For development environment setup, build instructions, and project architecture, see the [README](README.md#requirements).

**Key setup steps:**
1. Follow [Build Instructions](README.md#build-instructions) to set up the project
2. Configure Git hooks: `git config core.hooksPath .githooks`
3. Configure code signing in Xcode (see [Code Signing Setup](README.md#code-signing-setup))

## Code Style

This project enforces consistent code style using automated tools.

### SwiftFormat

Configuration: [`.swiftformat`](.swiftformat)

Key settings:
- 4-space indentation
- LF line endings
- 130 character line width
- Swift 6.0 compatibility

Run manually: `swiftformat .`

### SwiftLint

Configuration: [`.swiftlint.yml`](.swiftlint.yml)

Run manually: `swiftlint`

### Pre-commit Hooks

The Git hooks in `.githooks/` automatically run before each commit:

1. **swiftformat** - Auto-formats code and stages changes
2. **swiftlint --strict** - Enforces Swift style rules
3. **git-secrets** - Prevents accidental credential commits
4. **xcodegen** - Regenerates the Xcode project

If a hook fails, fix the issues and retry your commit.

## Making Changes

### Branching Strategy

- `main` - Stable release branch
- Feature branches - `feature/<description>`
- Bug fixes - `fix/<description>`

### Commit Messages

Write clear, descriptive commit messages:
- Use present tense ("Add feature" not "Added feature")
- Keep the first line under 72 characters
- Reference issue numbers when applicable

### Pull Request Process

1. Fork the repository and create your branch from `main`
2. Make your changes with appropriate tests
3. Ensure all pre-commit hooks pass
4. Update documentation if needed
5. Submit a pull request with a clear description

### What We Look For

- Code follows the existing patterns in the codebase
- Changes are focused and minimal
- No unnecessary dependencies added
- Privacy-preserving (no analytics, tracking, or external data collection)

## Voice Model Checksums

Voice models are downloaded from GitHub at runtime. For supply chain security, we verify model integrity using SHA256 checksums stored in [`SpeakTheWeb/Models/ModelManifest.swift`](SpeakTheWeb/Models/ModelManifest.swift).

### Verifying Checksums Before Release

Before each app release, verify all model checksums are current:

```bash
# 1. Download each model from the official release
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2

# 2. Compute SHA256 checksum
shasum -a 256 vits-piper-en_US-amy-medium.tar.bz2

# 3. Get file size in bytes
stat -f%z vits-piper-en_US-amy-medium.tar.bz2  # macOS
# or: stat --printf="%s" vits-piper-en_US-amy-medium.tar.bz2  # Linux

# 4. Compare with values in ModelManifest.swift
```

### Adding a New Model

1. Download the model archive from the [official sherpa-onnx release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)
2. Compute the SHA256 checksum and file size (see commands above)
3. Add an entry to the `knownModels` dictionary in `ModelManifest.swift`:

```swift
"vits-piper-<language>-<voice>-<quality>": Entry(
    sha256: "<lowercase-hex-sha256>",
    releaseTag: "tts-models",
    compressedSize: <size-in-bytes>,
    sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/<filename>.tar.bz2"
)
```

4. Test the model downloads and verifies correctly in the app

### If Upstream Changes a Model

If the sherpa-onnx project updates a model file (same filename, different content):

1. The app will reject the new file due to checksum mismatch
2. Update `ModelManifest.swift` with the new checksum and size
3. Release an app update for users to get the new model

This is intentional — it prevents silent changes to model files.

### Placeholder Checksums

During development, models may have `PLACEHOLDER_CHECKSUM_REQUIRED` as the checksum. These are skipped in DEBUG builds but **rejected in RELEASE builds**. All placeholders must be replaced with real checksums before App Store submission.

## Reporting Issues

- Check existing issues before creating a new one
- Include reproduction steps
- Include device/OS version information
- For crashes, include relevant logs

## Security

For security vulnerabilities, please see [SECURITY.md](SECURITY.md) for our responsible disclosure policy.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
