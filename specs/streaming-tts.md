# Streaming TTS

**Status**: Draft (pending validation of performance optimizations)
**Depends on**: `specs/sherpa-performance-optimizations-v1.md`

## Overview

Enable streaming TTS generation to reduce time-to-first-audio. Instead of generating the complete audio before playback, stream audio chunks as they're generated.

## UX Constraints During Streaming Generation

While audio is still being generated:

| Control | Enabled | Notes |
|---------|---------|-------|
| Play/Pause | Yes | Essential |
| Forward seek/skip | No | Audio doesn't exist yet |
| Backward seek/skip | Maybe | If buffering already-played audio |
| TOC section navigation | No | Requires audio that may not exist |
| "Start reading from here" | No | Same as seek |
| Cancel generation | Maybe | If low effort |

## UI Feedback

- Existing "Generating audio..." message is sufficient
- Append: "Playback controls temporarily disabled" (or similar)
- No determinate progress bar — streaming generation length is unknown until complete
- Once generation completes, all controls re-enable

## Implementation Considerations

### Backward Seek
- Feasibility depends on whether streaming buffers already-played audio
- If buffering for gapless playback (likely), backward seek within generated portion is nearly free
- Track `generatedDuration` vs `playbackPosition`

### Cancel Generation
- Requires Sherpa API support for aborting mid-generation
- Optional for v1 streaming

### Audio Buffering Strategy
- **Buffer type**: Ring buffer with bounded history
- **Max buffer size**: 150MB (covers typical article length)
- **Flow control**: High-water mark (80%) pauses generation, low-water mark (50%) resumes
- **Memory pressure**: If OS signals memory pressure, pause generation and evict oldest chunks beyond playback position

### Failure Modes & Recovery

| Failure | Detection | Response | UX |
|---------|-----------|----------|-----|
| Buffer underrun | Playback catches generation | Pause playback, continue generation | Fade or pause (decide during impl); show "Buffering..." |
| Model error mid-stream | Sherpa returns error | Retry with backoff (1s, 2s, 4s), max 3 attempts | "Retrying..." toast |
| Model load failure | Init fails | Fall back to batch generation | "Streaming unavailable, generating full audio..." |
| Repeated stream failures | 3+ consecutive errors | Abort streaming, fall back to batch | "Switching to standard generation..." |
| OS memory pressure | `didReceiveMemoryWarning` | Pause generation, evict old chunks | No visible change unless underrun |

### Retry Policy
- **Strategy**: Exponential backoff (1s → 2s → 4s)
- **Max attempts**: 3 per failure type
- **Fallback**: After 3 failures, abandon streaming and fall back to batch generation
- **Reset**: Successful chunk generation resets retry counter

## Open Questions

1. Does Sherpa's streaming API support cancellation?
2. What's the minimum buffer size for gapless playback?
3. How to handle model switch mid-stream?
4. Memory budget for audio buffer on low-end devices?

## References

- Current TTS implementation: `SpeakTheWeb/Services/SherpaSpeechService.swift`
- Performance optimizations: `specs/sherpa-performance-optimizations-v1.md`
