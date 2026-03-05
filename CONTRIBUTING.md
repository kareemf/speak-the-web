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

## Reporting Issues

- Check existing issues before creating a new one
- Include reproduction steps
- Include device/OS version information
- For crashes, include relevant logs

## Security

For security vulnerabilities, please see [SECURITY.md](SECURITY.md) for our responsible disclosure policy.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
