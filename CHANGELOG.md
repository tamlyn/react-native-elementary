# Changelog

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