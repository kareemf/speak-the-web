# URL Reader

An iOS app that reads web pages aloud using text-to-speech. Share a URL from Safari and listen to the content with playback controls and content navigation.

## Features

### Core Features
- **URL Input**: Paste or type any URL to fetch article content
- **Safari Share Extension**: Share directly from Safari's share sheet ("Read Aloud")
- **Text-to-Speech**: Using iOS's AVSpeechSynthesizer
- **Playback Controls**:
  - Play / Pause / Stop / Skip
  - Seekable progress bar
- **Speed Controls**: 0.5x, 0.75x, 1x, 1.25x, 1.5x, 1.75x, 2x

### Additional Features
- **Table of Contents**: Auto-generated from HTML semantic elements (h1-h6)
- **Section Navigation**: Jump directly to any section
- **Voice Selection**: Choose from all available iOS voices
- **Voice Preview**: Test voices before selecting
- **Background Audio**: Continues playing when app is backgrounded

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- macOS Sonoma 14.0+ (for development)

## Build Instructions

### Prerequisites

1. Install Xcode 15+ from the Mac App Store
2. Install Xcode Command Line Tools:
   ```bash
   xcode-select --install
   ```

### Building from Command Line

```bash
# Navigate to project directory
cd URLReader

# Build for iOS Simulator (Debug)
xcodebuild -project URLReader.xcodeproj \
  -scheme URLReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  build

# Build for iOS Simulator (Release)
xcodebuild -project URLReader.xcodeproj \
  -scheme URLReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Release \
  build

# Build for device (requires signing)
xcodebuild -project URLReader.xcodeproj \
  -scheme URLReader \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

### Building from Xcode

1. Open `URLReader.xcodeproj` in Xcode
2. Select your target device or simulator
3. Press `Cmd + B` to build, or `Cmd + R` to build and run

### Code Signing Setup

Before building for a physical device:

1. Open the project in Xcode
2. Select the **URLReader** target
3. Go to **Signing & Capabilities**
4. Select your Development Team
5. Repeat for the **URLReaderShare** extension target
6. Enable **App Groups** capability with identifier: `group.com.kareemf.URLReader`

### Install Required Tooling

This project relies on a few CLI tools for consistent builds and linting:

```bash
brew install git-secrets xcodegen swiftformat swiftlint
```

- **git-secrets** prevents accidental commits of credentials/keys.
- **xcodegen** regenerates the Xcode project from `project.yml`.
- **swiftformat** (lint mode) enforces formatting; run `swiftformat .` to auto-fix.
- **swiftlint** enforces Swift style rules.

After updating `project.yml`, regenerate the project with:

```bash
xcodegen generate
```

> **Note**: If you don't use XcodeGen, you can still use the pre-generated `.xcodeproj` file directly, but any project file changes should be made through `project.yml`.

### 3. Configure Git Hooks

This project includes Git hooks that run checks before every commit:

1. `swiftformat` — auto-formats tracked files, re-stages the changes, then verifies formatting via lint mode.
2. `swiftlint --strict` — enforces Swift style rules.
3. `git-secrets` — prevents accidental commits of credentials/keys.
4. `xcodegen` — regenerates the Xcode project to keep it aligned with `project.yml`.

Then point Git at the repo-local hooks directory:

```bash
git config core.hooksPath .githooks
```

The pre-commit hook will fail (with actionable messaging) if any tool is missing or surfaces issues. Fix them (e.g., run `swiftformat .`, resolve lint warnings, rerun XcodeGen) and reattempt the commit. Formatting fixes performed by the hook are automatically staged, so you can simply re-run your commit afterward.

## Testing

### Running Tests from Command Line

```bash
# Run unit tests on simulator
xcodebuild test \
  -project URLReader.xcodeproj \
  -scheme URLReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath TestResults

# Run tests with verbose output
xcodebuild test \
  -project URLReader.xcodeproj \
  -scheme URLReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  | xcpretty
```

### Running Tests from Xcode

1. Open `URLReader.xcodeproj`
2. Press `Cmd + U` to run all tests

### Manual Testing Checklist

- [ ] Enter a URL and fetch content
- [ ] Play/pause/stop functionality works
- [ ] Speed control changes playback rate
- [ ] Skip forward/backward works
- [ ] Progress bar is accurate and seekable
- [ ] Table of contents shows headings
- [ ] Tapping TOC item navigates correctly
- [ ] Voice settings allow changing voice
- [ ] Background audio continues playing
- [ ] Safari share extension appears in share sheet
- [ ] Sharing from Safari opens app with URL

## Project Structure

```
URLReader/
├── URLReader.xcodeproj/          # Xcode project file
├── URLReader/                    # Main app target
│   ├── URLReaderApp.swift        # App entry point & deep link handling
│   ├── Info.plist                # App configuration
│   ├── URLReader.entitlements    # App Groups entitlement
│   ├── Models/
│   │   └── Article.swift         # Article & section data models
│   ├── Services/
│   │   ├── ContentExtractor.swift # HTML fetching & parsing
│   │   └── SpeechService.swift    # Text-to-speech engine
│   ├── ViewModels/
│   │   └── ReaderViewModel.swift  # Main view model
│   ├── Views/
│   │   ├── ContentView.swift      # Root view
│   │   ├── URLInputView.swift     # URL input screen
│   │   ├── ArticleReaderView.swift # Article display
│   │   ├── PlaybackControlsView.swift # Playback UI
│   │   ├── TableOfContentsView.swift  # TOC navigation
│   │   └── VoiceSettingsView.swift    # Voice/speed settings
│   └── Assets.xcassets/          # App icons & colors
├── ShareExtension/               # Safari Share Extension target
│   ├── ShareViewController.swift  # Share UI controller
│   ├── Info.plist                # Extension configuration
│   └── ShareExtension.entitlements # App Groups entitlement
└── README.md                     # This file
```

## Architecture

### Design Pattern
- **MVVM** (Model-View-ViewModel) with SwiftUI
- `@ObservableObject` for reactive state management
- `@EnvironmentObject` for dependency injection

### Key Components

| Component | Responsibility |
|-----------|----------------|
| `ContentExtractor` | Fetches URLs, parses HTML, extracts text and headings |
| `SpeechService` | Wraps AVSpeechSynthesizer, manages playback state |
| `ReaderViewModel` | Coordinates UI state, handles user actions |
| `ShareViewController` | Receives URLs from Safari, launches main app |

### Data Flow
```
Safari → ShareExtension → App Groups → URLReaderApp → ReaderViewModel
                                              ↓
URL Input → ContentExtractor → Article → SpeechService → Audio Output
```

## Safari Share Extension

The app includes a Share Extension that appears as "Read Aloud" in Safari's share sheet.

### How It Works
1. User taps Share in Safari
2. Selects "Read Aloud" from the share sheet
3. Extension saves URL to App Groups shared storage
4. Extension launches main app via URL scheme (`urlreader://`)
5. Main app reads URL from shared storage and starts loading

### App Groups Configuration
Both the main app and extension use the App Group: `group.com.kareemf.URLReader`

## Customization

### Changing Bundle Identifier
1. Update `PRODUCT_BUNDLE_IDENTIFIER` in project settings
2. Update App Group identifier in both entitlements files
3. Update `UserDefaults(suiteName:)` calls in code

### Adding New Voices
The app automatically discovers all installed iOS voices. Users can download additional voices in:
**Settings → Accessibility → Spoken Content → Voices**

## Troubleshooting

### Build Errors

**"Signing requires a development team"**
- Select a development team in Xcode's Signing & Capabilities

**"App Groups capability not enabled"**
- Add App Groups capability to both targets in Xcode

### Runtime Issues

**Share extension doesn't appear**
- Ensure the extension is built and installed with the main app
- Check that the extension's Info.plist activation rules are correct

**Audio doesn't play in background**
- Verify `UIBackgroundModes` includes `audio` in Info.plist
- Ensure audio session is configured for `.playback` category

## License

MIT License
