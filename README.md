# react-native-elementary

> Use [Elementary Audio][elem] in your React Native app

This is alpha quality software. **iOS only for now**, PRs welcome for Android support.

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

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
