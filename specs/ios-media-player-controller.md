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
