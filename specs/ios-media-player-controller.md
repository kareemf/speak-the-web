# iOS Media Player Controller

## Background
Recent changes introduced shared audio-session setup in multiple engines. This can cause AVSpeech to fail on first play if another engine activates the shared AVAudioSession at launch. We want immediate playback with predictable audio-session ownership and clear logging to diagnose regressions.

## Goals
- Ensure immediate AVSpeech playback with no artificial delays.
- Prevent inactive engines from touching the shared AVAudioSession.
- Centralize audio-session activation/deactivation and logging.
- Keep remote-control commands and Now Playing metadata accurate.

## Non-goals
- Redesign Sherpa model download/caching.
- Change current UI flows beyond what is needed for playback correctness.

## Proposal
Introduce a single controller that owns engine instances, audio-session lifecycle, and playback state updates.

### Components
- MediaPlaybackController (new)
  - Owns and switches between engines.
  - Owns a single AudioSessionCoordinator.
  - Exposes play/pause/stop/seek APIs to the view model.
  - Emits playback state for Now Playing updates.

- AudioSessionCoordinator (new)
  - Single entry point for AVAudioSession configuration.
  - Activates only on playback intent.
  - Deactivates on stop or when switching engines (optional on pause).
  - Logs every change with previous and new state.

- Engine protocol (new)
  - Functions: loadContent, play, pause, stop, seek, setRate.
  - Properties: isPlaying, isPaused, progress, duration.

### Initialization policy
Support a policy enum so the default can be tuned without a refactor.

- selectedAtLaunch
  - Instantiate only the persisted selected engine on app launch.
  - Do not activate the audio session until play is requested.
  - If the user switches engines, initialize the new engine lazily.

- onDemand
  - Instantiate no engine at launch.
  - Initialize the first engine only when the user presses play or opens settings that require it.

Recommended default: selectedAtLaunch with deferred audio-session activation.
This keeps immediate playback while avoiding early audio-session ownership by inactive engines.

### Playback flow
1. ViewModel calls MediaPlaybackController.play().
2. Controller calls AudioSessionCoordinator.activate(for: selectedEngine).
3. Controller calls engine.play().
4. Controller publishes playback state to update Now Playing.

### Engine switch flow
1. Controller stops current engine.
2. Controller deactivates audio session (unless the target engine will start immediately).
3. Controller initializes target engine (if needed).
4. Controller updates Now Playing and command center.

## Logging and Diagnostics
Add structured logs that make ownership and state transitions explicit.

### Required log events
- AudioSession
  - activate/deactivate calls with category, mode, options, and result.
  - isOtherAudioPlaying, secondaryAudioShouldBeSilencedHint.
  - currentRoute inputs/outputs.
  - interruption begin/end with reason.
  - route change reason.

- AVSpeech engine
  - play/pause/stop calls and internal isSpeaking/isPaused state.
  - didStart/didFinish/didCancel callbacks.
  - retry start attempts with attempt ID.

- Sherpa engine
  - engine.start success/failure with error.
  - prepare/generate phases and completion.

### Example log fields
- engine=avSpeech|sherpaOnnx
- action=activate|deactivate|play|pause|stop
- sessionCategory, sessionMode, sessionOptions
- routeOutputs, routeInputs
- isOtherAudioPlaying
- errorCode, errorMessage
- attemptId

## Migration Steps
1. Introduce AudioSessionCoordinator and route all session usage through it.
2. Update SpeechService and SherpaSpeechService to remove audio-session configuration from init.
3. Implement MediaPlaybackController and move play/pause/stop/seek logic from ReaderViewModel.
4. Wire NowPlayingManager updates to controller state.
5. Add structured logging and verify with AVSpeech playback.

## Risks
- Deferring engine init may add a small one-time cost on first play.
- Centralizing the session may require careful handling of background playback.

## Success Criteria
- AVSpeech plays immediately on first press without error logs.
- Session activation only occurs on playback intent.
- Logs clearly show which engine owns the session and when transitions occur.

## Current Issues (as of latest logs)
- Playback fails to start for both AVSpeech and Sherpa.
- Audio session activation fails with `NSOSStatusErrorDomain Code=-50` and `SessionCore.mm:517 Failed to set properties`.
- `MRNowPlaying` reports missing entitlement `com.apple.mediaremote.set-playback-state` when setting playback state.
- App Group prefs warning from `CFPrefsPlistSource` (likely unrelated to playback).

## Fixes Attempted
- Centralized audio session ownership in `AudioSessionCoordinator`.
- Deferred session activation until playback intent.
- Added `allowAirPlay` and `allowBluetoothA2DP` options.
- Moved playback kick to main runloop after session activation.
- Added AVSpeech pre-warm/reset (`prepareForPlayback()`).
- Updated Now Playing to set `playbackState` and dispatch remote commands on main.

## What to Try Next
- Remove `allowAirPlay`/`allowBluetoothA2DP` options temporarily to see if `Code=-50` is driven by invalid option combinations.
- Try `AVAudioSession.Mode.default` (or `.voicePrompt`) instead of `.spokenAudio` to test if mode is rejected.
- Log pre-activation session state (category, mode, options) and error source (setCategory vs setActive) to isolate the failing call.
- Run once with Bluetooth disconnected and route to built-in speaker to rule out A2DP route constraints.
- Consider removing `MPNowPlayingInfoCenter.playbackState` updates (private entitlement) to reduce noise in logs.

## Implementation Plan (Current PR)
Phase 1: Audio session safety and diagnostics
- Remove all AVAudioSession configuration from `SpeechService`, `SherpaSpeechService`, and voice preview.
- Update `AudioSessionCoordinator` to use `.playback` + `.default` + `[.duckOthers]` and add pre-state logging plus separate setCategory/setActive error logs.
- Test: confirm first-play AVSpeech works and `Code=-50` is gone.
- Flip: once confirmed, switch `AudioSessionCoordinator` mode to `.spokenAudio` and retest in this PR.

Phase 2: Controller wiring and selectedAtLaunch
- Route playback through `MediaPlaybackController` and stop using services directly in `ReaderViewModel`.
- Instantiate only the selected engine at launch; lazy-init the other engine on first use.
- Keep AVAudioSession activation only on play intent.
- Test: switching engines stops the previous engine and playback remains stable.

Phase 3: Now Playing integration
- Drive `NowPlayingManager` from `MediaPlaybackController` state.
- Remove `MPNowPlayingInfoCenter.playbackState` updates.
- Test: Control Center play/pause/skip/seek works and Now Playing info updates without entitlement warnings.

Phase 4: Post-verify cleanup
- Confirm logging is sufficient and remove any temporary debug-only behavior if added.
- Test: run through AVSpeech and Sherpa playback flows end-to-end.

## OS Playback Controls Plan
Primary goal: ensure OS-level playback controls (headphones buttons, lock screen, Control Center) work reliably for both engines.

### Phase 1: Prerequisites and session policy
- Verify Background Modes includes audio (`UIBackgroundModes` = `audio`) so playback and controls persist when locked or backgrounded.
- Keep `AVAudioSession` category `.playback` + mode `.spokenAudio` active while playing or paused; only deactivate on explicit stop.
- Ensure remote command handlers always activate the session before starting playback.

### Phase 2: Now Playing metadata correctness
- Populate Now Playing immediately on play start (title, artist, duration, elapsed, playback rate).
- On pause, set `MPNowPlayingInfoPropertyPlaybackRate` to `0` but keep metadata to preserve lock screen UI.
- Update elapsed/duration on seek and via a periodic timer while playing.
- Optional: add artwork if article metadata is available.

### Phase 3: Remote command center reliability
- Configure `MPRemoteCommandCenter` once and remove old targets on reconfigure to avoid duplicates.
- Enable or disable commands based on capability (seek only if duration exists).
- Map commands to controller actions: play, pause, toggle, skip forward/back (15s), and seek.
- Ensure command handlers return `.success` only after the action is scheduled.
- Support lock screen scrubber via `changePlaybackPositionCommand`.
- Optional: ignore or map `changePlaybackRateCommand` if we want OS-driven rate changes.

### Phase 4: Interruptions and route changes
- On interruption begin: pause and record `wasPlayingBeforeInterruption`.
- On interruption end: resume only if `shouldResume` and `wasPlayingBeforeInterruption` is true.
- On route change `.oldDeviceUnavailable` (headphones unplug): pause and update Now Playing.
- Keep logs for interruption/route-change reasons and resulting playback action.
- Treat Bluetooth disconnect as `.oldDeviceUnavailable`; optionally inspect previous route to differentiate and log.

### Phase 5: Verification
- Lock screen shows controls and metadata while playing; play/pause works.
- Headphones play/pause toggles playback when app is in background.
- Control Center skip/seek works and updates elapsed time.
- Behavior verified for both AVSpeech and Sherpa engines.
