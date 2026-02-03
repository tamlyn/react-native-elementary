import * as React from 'react';
import { useState, useRef, useEffect } from 'react';

import { StyleSheet, View, Text, Button, Platform } from 'react-native';
import {
  useRenderer,
  loadAudioResource,
  unloadAudioResource,
  AudioResourceInfo,
} from 'react-native-elementary';
import RNFS from 'react-native-fs';
import { el } from '@elemaudio/core';

const SAMPLE_FILES = ['kick.wav', 'snare.wav', 'hihat.wav'] as const;

const getSamplePath = async (filename: string): Promise<string> => {
  if (Platform.OS === 'android') {
    const dest = `${RNFS.DocumentDirectoryPath}/${filename}`;
    const exists = await RNFS.exists(dest);
    if (!exists) {
      await RNFS.copyFileAssets(`samples/${filename}`, dest);
    }
    return dest;
  }
  return `${RNFS.MainBundlePath}/samples/${filename}`;
};

export default function App() {
  const { core } = useRenderer();
  const [loadedSamples, setLoadedSamples] = useState<
    Record<string, AudioResourceInfo>
  >({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const triggerRef = useRef<Record<string, number>>({
    kick: 0,
    snare: 0,
    hihat: 0,
  });
  const lastPlayTime = useRef<Record<string, number>>({});

  const loadSamples = async () => {
    setLoading(true);
    setError(null);

    try {
      const loaded: Record<string, AudioResourceInfo> = {};

      for (const file of SAMPLE_FILES) {
        const key = file.replace('.wav', '');
        const path = await getSamplePath(file);
        const info = await loadAudioResource(key, path);
        loaded[key] = info;
      }

      setLoadedSamples(loaded);
    } catch (e) {
      console.error('Failed to load samples:', e);
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    return () => {
      Object.keys(loadedSamples).forEach((key) => {
        unloadAudioResource(key).catch(console.error);
      });
    };
  }, [loadedSamples]);

  const playSample = (key: string) => {
    if (!loadedSamples[key]) return;

    const now = Date.now();
    const lastTime = lastPlayTime.current[key] || 0;
    if (now - lastTime < 100) return;
    lastPlayTime.current[key] = now;

    triggerRef.current[key] = (triggerRef.current[key] || 0) + 1;

    const sample = el.sample(
      { path: key, mode: 'trigger', key: `${key}-sample` },
      el.const({ key: `${key}-trig`, value: triggerRef.current[key] }),
      1
    );

    core.render(sample, sample);
  };

  const playBeat = () => {
    if (Object.keys(loadedSamples).length === 0) return;

    const bpm = 126;
    const beatFreq = bpm / 60;

    const kick = el.mul(
      el.sample({ path: 'kick', mode: 'trigger' }, el.train(beatFreq), 1),
      0.9
    );
    const snare = el.mul(
      el.sample({ path: 'snare', mode: 'trigger' }, el.train(beatFreq / 2), 1),
      0.6
    );
    const hihat = el.mul(
      el.sample({ path: 'hihat', mode: 'trigger' }, el.train(beatFreq * 2), 1),
      0.35
    );

    const mix = el.add(kick, el.add(snare, hihat));
    core.render(mix, mix);
  };

  const stop = () => {
    core.render();
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>VFS Audio Demo</Text>

      {error && <Text style={styles.error}>Error: {error}</Text>}

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>1. Load Samples</Text>
        <Button
          title={loading ? 'Loading...' : 'Load Samples'}
          onPress={loadSamples}
          disabled={loading}
        />
        {Object.entries(loadedSamples).map(([key, info]) => (
          <Text key={key} style={styles.sampleInfo}>
            {key}: {info.channels}ch, {info.sampleRate}Hz,{' '}
            {info.durationMs.toFixed(0)}ms
          </Text>
        ))}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>2. Play Individual Samples</Text>
        <View style={styles.buttonRow}>
          <Button
            title="Kick"
            onPress={() => playSample('kick')}
            disabled={!loadedSamples.kick}
          />
          <Button
            title="Snare"
            onPress={() => playSample('snare')}
            disabled={!loadedSamples.snare}
          />
          <Button
            title="HiHat"
            onPress={() => playSample('hihat')}
            disabled={!loadedSamples.hihat}
          />
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>3. Play Beat</Text>
        <Button
          title="Play 4-on-the-floor (126 BPM)"
          onPress={playBeat}
          disabled={Object.keys(loadedSamples).length === 0}
        />
      </View>

      <View style={styles.section}>
        <Button title="Stop" onPress={stop} />
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Legacy Test</Text>
        <Button
          title="Play 440Hz Tone"
          onPress={() => core.render(el.cycle(440), el.cycle(440))}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
    backgroundColor: '#1a1a2e',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    color: '#eee',
  },
  section: {
    marginVertical: 10,
    alignItems: 'center',
    width: '100%',
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#aaa',
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 10,
  },
  sampleInfo: {
    fontSize: 12,
    color: '#6f6',
    marginTop: 4,
  },
  error: {
    color: '#f66',
    marginBottom: 10,
  },
});
