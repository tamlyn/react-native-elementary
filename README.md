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

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
