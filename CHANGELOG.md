# Changelog

## Unreleased

### Features

- Add bounded PCM readback for native WAV, MP3 and FLAC imports through `loadAudioResourceForReadback` and `readAudioResourcePCM`. Ordinary VFS loading remains unchanged; M4A/AAC is not supported.

## 0.4.1-beta.4

### Bug Fixes

- **ios:** Prime the Simulator audio route before cold engine startup and reject unusable output formats.
- **ios:** Adapt variable-size host callbacks to fixed DSP blocks, preserving feedback history and preventing buffer overruns. Carry-over can add up to one runtime block of latency.
- **ios:** Serialize runtime event collection with graph updates and route replacement; deliver events after unlocking so listeners can safely re-enter.
- **ios:** Keep `getAudioInfo` status-only: before initialization it returns zero channels/sample rate and false readiness/running flags without starting audio.

## 0.4.1-beta.2

### Features

- **Event polling opt-in** — `startEventPolling()`, `stopEventPolling()`, `configureEventPolling(intervalMs)` to control runtime event polling (el.snapshot, el.meter, el.scope, el.fft). Polling is no longer started automatically, reducing JS thread overhead for apps that don't need events.

### Bug Fixes

- **Android new arch:** Add missing `startEventPolling`, `stopEventPolling`, `configureEventPolling` overrides in `ElementaryTurboModule.java` (fixes build failure)
- **Lint:** Fix Prettier formatting for `configureAudioSession` params in `NativeElementary.ts`

## 0.4.1-beta.1

### Features

- **ios:** Expose explicit audio session controls (configuration options for audio session category, mode, and options)
- **setProperty** for real-time parameter updates on both iOS and Android
- **getBundlePath** and **getAudioInfo** accessors on iOS; **getBundlePath** and **setProperty** on Android bridge
- **Runtime events** — poll `processQueuedEvents` and emit runtime events to JavaScript on both platforms

### Bug Fixes

- **ios:** Configure `AVAudioSession` before engine init to prevent buffer mismatch
- **ios:** Avoid invalid audio session active check
- **ios:** Use raw value `0x4` for `allowBluetoothHFP` option
- **android:** Handle audio interruptions, config changes, and channel count safety
- **android:** Improve audio device recovery after focus loss
- **android:** Lock `runtimeMutex` in `loadAudioResource`/`unloadAudioResource` to prevent heap corruption
- **android:** Add mutex to prevent heap corruption from concurrent runtime access
- Defer audio engine restart on config change to prevent RPC deadlock

## 0.4.0

- VFS audio resource loading and upgrade to Elementary v4
- New architecture support

## 0.3.0

- Initial public release

## 0.2.0 - 0.2.2

- Early development releases