# react-native-elementary

> Use [Elementary Audio][elem] in your React Native app

This is alpha quality software.

[elem]: https://elementary.audio

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