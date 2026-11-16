# react-native-elementary

> Use [Elementary Audio][elem] in your React Native app

[![Alpha](https://img.shields.io/badge/status-alpha-orange)](https://github.com/tamlyn/react-native-elementary/releases)

[elem]: https://elementary.audio

## Project status

Alpha. The API is subject to change.

### Supported platforms

- iOS
- Android

### Supported features

- Native Elementary Audio renderer via `useRenderer` hook
- Real-time `setProperty` for graph parameter updates
- iOS audio session configuration and management
- Configurable event polling (`el.snapshot`, `el.meter`, `el.scope`, `el.fft`)
- Audio resource loading via VFS and bounded PCM readback

### Known issues

- Native node types (`el.metro`, `el.time`, `el.fft`, `el.convolve`) are not yet
  supported (see [#4][i4])
- Audio I/O may not update automatically when device connection changes;
  engine restart on route change is handled, re-graph against new route is pending
  (see [#15][i15])

[i4]: https://github.com/tamlyn/react-native-elementary/issues/4
[i15]: https://github.com/tamlyn/react-native-elementary/issues/15

## Installation

```sh
npm install react-native-elementary
```

## Usage

```jsx
import { el } from '@elemaudio/core';
import { useRenderer } from 'react-native-elementary';

const MyComponent = () => {
  const { core } = useRenderer();

  if (!core) {
    return <Text>Initialising audio...</Text>;
  }

  return (
    <View>
      <Button
        title="Play"
        onPress={() => core.render(el.cycle(440), el.cycle(441))}
      />
    </View>
  );
};
```

## iOS audio session

For simple playback apps, no setup is required. `react-native-elementary` lazily
configures and activates an iOS `AVAudioSession` with playback-oriented defaults
before the native audio engine starts.

If your app needs different iOS audio behavior, configure the session before the
first render or resource load:

```tsx
import { configureAudioSession } from 'react-native-elementary';

configureAudioSession({
  iosCategory: 'playback',
  iosMode: 'default',
  iosOptions: ['mixWithOthers', 'allowBluetoothA2DP'],
});
```

If your app or another audio library owns `AVAudioSession`, opt out of
Elementary's session management before the first render or resource load:

```tsx
import { disableAudioSessionManagement } from 'react-native-elementary';

disableAudioSessionManagement();
```

`activateAudioSession()` and `deactivateAudioSession()` are also available when
you need to explicitly control the iOS session lifecycle. These audio-session
helpers are no-ops on Android.

## Reading audio files

The native decoder supports **WAV, MP3 and FLAC** on iOS and Android. Use
`loadAudioResource` for VFS playback. If you need decoded samples for slicing,
resampling or waveform analysis, use the readback API:

```tsx
import {
  loadAudioResourceForReadback,
  readAudioResourcePCM,
  unloadAudioResource,
} from 'react-native-elementary';

const key = 'import-1'; // Use a unique key for each import.
try {
  const info = await loadAudioResourceForReadback(key, '/path/to/drums.flac');
  const frameCount = Math.min(16384, info.sampleCount);
  const pcm = await readAudioResourcePCM(key, 0, frameCount);
  // Process pcm, then read further chunks using later startFrame offsets.
} finally {
  await unloadAudioResource(key);
}
```

`loadAudioResourceForReadback` returns the same `AudioResourceInfo` metadata as
ordinary resource loading. PCM chunks are interleaved floats at the file's source
sample rate. Offsets and counts are **frames**, so a stereo chunk contains twice
as many scalar samples as its frame count.

Readback loads are limited to mono/stereo, 8–192 kHz, 60 seconds and 32 MiB of
decoded float samples per file. These limits are checked before PCM allocation;
they do not restrict ordinary VFS loads. Each read accepts integer offsets and
1–16,384 frames, entirely inside the decoded file. Only explicit readback loads
retain PCM, and `unloadAudioResource` releases it. On iOS, decoding and unloading
readback-only files does not cold-start `AVAudioEngine`.

Missing, corrupt or unsupported files reject with `E_LOAD_FAILED`. Invalid ranges
or missing readback keys reject with `E_PCM_READ`. **M4A/AAC is not supported** by
the current decoder; convert those files to WAV, MP3 or FLAC first. MP3 may include
encoder delay/padding, so frame offsets refer to the PCM returned by its decoder.

Rebuild the native app and regenerate codegen/Pods when adopting these methods;
a JavaScript-only update cannot add the native bridge APIs.

## Event polling

By default, `react-native-elementary` does **not** start polling for runtime events. This avoids unnecessary JS thread overhead for apps that only use `setProperty` for real-time updates and don't need `el.snapshot`, `el.meter`, or `el.scope` data.

If your app needs snapshot/meter/scope events, opt in explicitly:

```tsx
import { startEventPolling, stopEventPolling, configureEventPolling } from 'react-native-elementary';

// Start polling at default ~30Hz (33ms)
await startEventPolling();

// Or configure a different rate before starting:
await configureEventPolling(100); // 100ms ≈ 10Hz (drift correction only)
await startEventPolling();

// Stop polling when you don't need events anymore:
await stopEventPolling();
```

### Listening for events

Events are emitted on the `elementaryEvent` channel via `NativeEventEmitter`. Each callback receives a single event object with a `type` field and event-specific data:

```tsx
import { NativeEventEmitter, NativeModules } from 'react-native';

const elementaryEmitter = new NativeEventEmitter(NativeModules.Elementary);

const subscription = elementaryEmitter.addListener('elementaryEvent', (event) => {
  // event = { type: 'snapshot', source: 'playhead', data: 1.25 }
  // event = { type: 'meter',   source: 'level',   data: 0.75 }
  // event = { type: 'scope',  data: [...] }
  console.log(event.type, event);
});

// Don't forget to remove on unmount:
subscription.remove();
```

### Polling rates

| Interval | Rate | Use case |
|----------|------|----------|
| 33ms | ~30Hz | Smooth metering, playhead UI |
| 100ms | ~10Hz | Drift correction only, minimal overhead |

Values are clamped to 10–1000ms.

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)