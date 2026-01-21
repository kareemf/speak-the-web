# Voice Models Spec

## Purpose & user problem
- Power users may want higher-quality, more natural voices than AVSpeechSynthesizer offers, including strong non-English options.
- The app should allow offline TTS with downloadable, on-device models without inflating the app bundle.

## Success criteria
- User can download a Piper model, switch engine, and speak an article fully offline (aside from article fetch unless already cached).
- Models are stored in the app sandbox; compressed archives are removed after extraction.
- Model list shows uncompressed sizes so users understand storage impact.

## Scope & constraints
- Support all Piper models matching: `vits-piper-<language>-<name>-medium.tar.bz2`
- Foreground-only downloads are acceptable for v1.
- Allow selecting, downloading, and removing models.
- Persist selected engine and selected model.
- Show download progress and state (not downloaded / downloading / downloaded / active).
- When Sherpa-onnx is selected, model download/selection is required before playback.

## Technical considerations
- Integrate Sherpa-onnx via a local SwiftPM wrapper that links `sherpa-onnx.xcframework` and `onnxruntime.xcframework` built from `build-ios.sh`.
- Download from GitHub Releases: https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
- Extract `.tar.bz2` into app sandbox (Application Support).
- Build a local model registry (e.g., JSON) with:
  - model ID (derived from filename)
  - language, name
  - download URL
  - uncompressed size (from release asset metadata)
  - local path to extracted files
  - selected flag / last used
- Use Sherpa-onnx wrapper to load selected model and synthesize audio offline.
- AVSpeechSynthesizer remains default engine; existing voice selection UI remains for AVSpeech.

## UX plan
- Add a new Settings screen with:
  - Engine selector: AVSpeechSynthesizer vs Sherpa-onnx
  - AVSpeech subsection: existing voice selection UI (move from current sheet)
  - Sherpa subsection: link to “Manage Models”
- “Manage Models” screen:
  - Group by Language; optionally secondary group/sort by size
  - Display model name, uncompressed size, status
  - Actions: Download, Delete, Select
  - Show current selection badge
  - Progress indicator for downloads
- Reader UI:
  - Playback uses the selected engine
  - If Sherpa selected without model, prompt user to download/select

## Out of scope
- Cloud TTS
- Custom voice cloning
- Streaming voices (see question below)

## TODOs
- Keep Sherpa-onnx local package build script up to date with upstream

## Current progress
- Settings UI supports toggling between AVSpeech and Sherpa, downloading models, selecting, and removing models.
- Model downloads/extraction/selection are working and persisted; missing files are validated and cleared with a user-facing error.
- Sherpa playback is working; generation shows phase state and has a watchdog timeout.
- Playback speed changes use `AVAudioUnitTimePitch` (no regeneration).
- Engine switching now applies the current playback speed.
- Sherpa seeking, skip controls, and TOC jumps update progress correctly without ending playback.

## Current issues
- Debug logging is still enabled in Sherpa playback and view model.
- Playback error alerts could offer a direct "Go to Models" action for faster recovery.

## Next steps / triage
- Remove or gate debug logging for release builds.
- Add a playback error CTA to open Settings → Sherpa Models when a model is missing.
- Consider tuning watchdog timeout thresholds after more on-device timing data.
