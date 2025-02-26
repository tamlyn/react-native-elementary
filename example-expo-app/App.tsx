import React, { useState } from 'react';
import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View, Button } from 'react-native';
import { useRenderer } from 'react-native-elementary';
import { el } from '@elemaudio/core';

export default function App() {
  const { core } = useRenderer();
  const [isPlaying, setIsPlaying] = useState(false);

  const playTone = () => {
    if (!core) return;

    setIsPlaying(true);
    const tone = el.cycle(el.const({ value: 440 }));
    core.render(tone, tone);
  };

  const stopTone = () => {
    if (!core) return;

    setIsPlaying(false);
    core.render(el.const({ value: 0 }), el.const({ value: 0 }));
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Elementary Audio in Expo</Text>
      <Button
        title={isPlaying ? 'Stop Sound' : 'Play Sound'}
        onPress={isPlaying ? stopTone : playTone}
      />
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 20,
  },
});
