# Sherpa Performance Optimization Plan

**Status**: Implemented
**Date**: 2026-01-23

## Current State (Before Optimization)

| Setting | Value | Location |
|---------|-------|----------|
| Provider | `"cpu"` | SherpaSpeechService.swift:313 |
| Threads | `2` (hardcoded) | SherpaSpeechService.swift:312 |
| Model reuse | None (new instance per generation) | SherpaSpeechService.swift:318 |
| Batch sentences | `1` (default) | Not explicitly set |
| Streaming | Out of scope | specs/voice-models.md |

---

## Optimizations Implemented

### 1. Provider Selection (High Priority)
**File**: `SpeakTheWeb/Services/SherpaSpeechService.swift`

**Investigation findings**:
- **XNNPACK**: Not available in current iOS Sherpa-ONNX build (confirmed via `session.cc` logs showing only `CoreMLExecutionProvider, CPUExecutionProvider`)
- **CoreML**: Causes `EXC_BAD_ACCESS` crash in `SherpaOnnxOfflineTtsGenerate` — appears to only support ASR models, not TTS
- **CPU**: Only reliable provider for TTS currently

**Implementation**: CPU-only with documentation of why alternatives don't work.

```swift
// Provider selection:
// - xnnpack: not available in current iOS build (session.cc logs show only CoreML + CPU)
// - coreml: causes EXC_BAD_ACCESS in SherpaOnnxOfflineTtsGenerate (may only support ASR, not TTS)
// - cpu: only reliable option for TTS currently
let provider = "cpu"
```

**Future**: If Sherpa adds TTS support for CoreML or XNNPACK, revisit this. The dynamic thread count optimization still applies.

### 2. Model Instance Reuse with Lifecycle Management (High Priority)
**File**: `SpeakTheWeb/Services/SherpaSpeechService.swift`

**Risk**: Overlapping generations, model switching mid-run, memory pressure.

**Implementation**: Cache TTS instance with proper locking and automatic invalidation.

```swift
private var cachedTTS: SherpaOnnxOfflineTtsWrapper?
private var cachedModelID: String?
private let ttsLock = NSLock()

func getOrCreateTTS(for record: SherpaModelRecord, ...) throws -> SherpaOnnxOfflineTtsWrapper {
    ttsLock.lock()
    defer { ttsLock.unlock() }

    // Invalidate if model changed
    if cachedModelID != record.id {
        cachedTTS = nil
        cachedModelID = nil
    }

    // Return cached if available
    if let existing = cachedTTS {
        return existing
    }

    // Create new instance with XNNPACK fallback...
}
```

**Teardown triggers**:
- `invalidateCachedModel()` called on model selection change in `updateModel()`
- Registered for `UIApplication.didReceiveMemoryWarningNotification`

### 3. Bounded Thread Configuration (Medium Priority)
**File**: `SpeakTheWeb/Services/SherpaSpeechService.swift`

**Risk**: Oversubscription on efficiency-core devices, contention with AVAudioSession.

**Implementation**: Dynamic thread count based on available processors.

```swift
private var optimalThreadCount: Int32 {
    let available = ProcessInfo.processInfo.activeProcessorCount
    // Use half of available cores, minimum 2, maximum 4
    // Leaves headroom for audio playback and UI
    return Int32(max(2, min(available / 2, 4)))
}
```

### 4. Batch Sentences (Deferred)
**Action**: Deferred until other optimizations are validated. May alter prosody, pauses, and pronunciation. Consider as user-configurable advanced setting if beneficial.

---

## Files Modified

- `SpeakTheWeb/Services/SherpaSpeechService.swift`
  - Added `#if canImport(UIKit)` for memory warning observer
  - Added `ttsLock`, `cachedTTS`, `cachedModelID` properties
  - Added `optimalThreadCount` computed property
  - Added `getOrCreateTTS(for:tokensPath:dataDir:)` method with CoreML/CPU fallback
  - Added `invalidateCachedModel()` method
  - Modified `init()` to register for memory warnings
  - Modified `updateModel(record:)` to invalidate cache on model change
  - Modified `prepareAudio()` to use cached TTS instance

---

## Verification Checklist

- [x] ~~Test CoreML on device~~ — CoreML crashes with TTS (EXC_BAD_ACCESS), CPU-only for now
- [ ] Time generation before/after model reuse
- [ ] Monitor memory with Instruments during extended use
- [ ] Test cancellation during generation with cached model
- [ ] Verify model switching clears cache properly
