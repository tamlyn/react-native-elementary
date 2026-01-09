import * as React from 'react';

import { StyleSheet, View, Text, Button } from 'react-native';
import { useRenderer } from 'react-native-elementary';
import { el } from '@elemaudio/core';

export default function App() {
  const { core } = useRenderer();

  if (!core) {
    return (
      <View style={styles.container}>
        <Text>Initialising audio...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text>Audio engine initialised</Text>
      <Button
        title="Play test tone"
        onPress={() => core.render(el.cycle(440), el.cycle(440))}
      />
      <Button title="Stop" onPress={() => core.render()} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
