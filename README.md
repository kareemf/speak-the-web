# URL Reader - iOS Text-to-Speech App

An iOS app that reads web articles aloud using text-to-speech. Drop in any URL and listen to the content with full playback controls.

## Features

### Must-Haves (Implemented)
- **URL Input**: Paste or type any URL to fetch article content
- **Text-to-Speech**: Uses iOS's built-in AVSpeechSynthesizer for high-quality speech
- **Playback Controls**:
  - Play/Pause
  - Stop
  - Skip forward (30 seconds)
  - Skip backward (15 seconds)
  - Seekable progress bar
- **Speed Controls**: Adjustable playback speed from 0.5x to 2x

### Nice-to-Haves (Implemented)
- **Table of Contents**: Automatically generated from HTML semantic elements (h1-h6 headings)
- **Section Navigation**: Jump directly to different sections of the article
- **Voice Selection**: Choose from all available iOS voices
- **Voice Preview**: Test voices before selecting
- **Background Audio**: Continues playing when app is backgrounded

## Architecture

```
URLReader/
├── URLReaderApp.swift          # App entry point
├── Models/
│   └── Article.swift           # Article and section data models
├── Services/
│   ├── ContentExtractor.swift  # HTML fetching and parsing
│   └── SpeechService.swift     # Text-to-speech engine
├── ViewModels/
│   └── ReaderViewModel.swift   # Main view model
└── Views/
    ├── ContentView.swift       # Root view
    ├── URLInputView.swift      # URL input screen
    ├── ArticleReaderView.swift # Article display
    ├── PlaybackControlsView.swift # Playback UI
    ├── TableOfContentsView.swift  # TOC navigation
    └── VoiceSettingsView.swift    # Voice/speed settings
```

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open `URLReader.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a simulator or device

## Usage

1. Launch the app
2. Enter a URL in the text field (e.g., `wikipedia.org/wiki/Swift`)
3. Tap "Fetch Article" to load the content
4. Use the play button to start listening
5. Adjust speed using the segmented control
6. Use the list icon to access the Table of Contents
7. Use the gear icon to change voices

## Technical Notes

### Content Extraction
The app uses a custom HTML parser that:
- Removes unwanted elements (scripts, styles, nav, etc.)
- Extracts main content from `<article>`, `<main>`, or content divs
- Preserves heading structure for TOC generation
- Decodes HTML entities
- Handles various character encodings

### Text-to-Speech
Uses `AVSpeechSynthesizer` with:
- Real-time progress tracking
- Word-by-word highlighting
- Background audio support
- Voice quality detection (enhanced voices prioritized)

### Permissions
- **Network Access**: Required to fetch URLs (configured in Info.plist)
- **Background Audio**: Enabled for continued playback

## License

MIT License
