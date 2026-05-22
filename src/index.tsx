import { NativeModules, Platform } from 'react-native';
import { Renderer } from '@elemaudio/core';
import { useRef } from 'react';
import NativeElementary, { type AudioResourceInfo } from './NativeElementary';

export type { AudioResourceInfo };

export type IOSAudioSessionCategory =
  | 'ambient'
  | 'soloAmbient'
  | 'playback'
  | 'record'
  | 'playAndRecord'
  | 'multiRoute';

export type IOSAudioSessionMode =
  | 'default'
  | 'voiceChat'
  | 'videoChat'
  | 'gameChat'
  | 'measurement'
  | 'moviePlayback'
  | 'spokenAudio'
  | 'voicePrompt'
  | 'videoRecording';

export type IOSAudioSessionOption =
  | 'mixWithOthers'
  | 'duckOthers'
  | 'defaultToSpeaker'
  | 'allowBluetoothA2DP'
  | 'allowBluetoothHFP'
  | 'allowAirPlay'
  | 'interruptSpokenAudioAndMixWithOthers';

export type AudioSessionOptions = {
  iosCategory?: IOSAudioSessionCategory;
  iosMode?: IOSAudioSessionMode;
  iosOptions?: IOSAudioSessionOption[];
};

const LINKING_ERROR =
  `The package 'react-native-elementary' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const Elementary = NativeElementary || NativeModules.Elementary;

const ElementaryModule =
  Elementary ??
  new Proxy(
    {},
    {
      get() {
        throw new Error(LINKING_ERROR);
      },
    }
  );

/** Returns the device audio sample rate */
export function getSampleRate(): Promise<number> {
  return ElementaryModule.getSampleRate();
}

/**
 * Activate Elementary's native iOS audio session.
 * No-ops on Android.
 */
export function activateAudioSession(): Promise<boolean> {
  return ElementaryModule.activateAudioSession();
}

/**
 * Deactivate Elementary's native iOS audio session.
 * No-ops on Android.
 */
export function deactivateAudioSession(): Promise<boolean> {
  return ElementaryModule.deactivateAudioSession();
}

/**
 * Configure Elementary's native iOS audio session before creating/using the renderer.
 * Defaults match Elementary's playback-oriented setup.
 * No-ops on Android.
 */
export function configureAudioSession({
  iosCategory = 'playback',
  iosMode = 'default',
  iosOptions = ['mixWithOthers', 'allowBluetoothA2DP'],
}: AudioSessionOptions = {}): void {
  ElementaryModule.configureAudioSession(iosCategory, iosMode, iosOptions);
}

/**
 * Disable Elementary's internal iOS audio session management.
 * Use this when the host app or another audio library owns AVAudioSession.
 * No-ops on Android.
 */
export function disableAudioSessionManagement(): void {
  ElementaryModule.disableAudioSessionManagement();
}

/** Load an audio file into the VFS for use with el.sample(), el.table(), etc. */
export function loadAudioResource(
  key: string,
  filePath: string
): Promise<AudioResourceInfo> {
  return ElementaryModule.loadAudioResource(key, filePath);
}

/** Unload an audio resource from the VFS */
export function unloadAudioResource(key: string): Promise<boolean> {
  return ElementaryModule.unloadAudioResource(key);
}

/** Get the app's documents directory path */
export function getDocumentsDirectory(): Promise<string> {
  return ElementaryModule.getDocumentsDirectory();
}

/** Get the app bundle's resource path (for loading bundled assets) */
export function getBundlePath(): Promise<string> {
  return ElementaryModule.getBundlePath();
}

/**
 * Update a property on a graph node without re-rendering the entire graph.
 * This operates directly on the audio thread — ideal for real-time MIDI
 * note triggering, parameter automation, and any time-critical updates.
 *
 * @param nodeHash - The elem node hash (from node.hash after creating with el.*)
 * @param key - The property name to update (e.g. 'value')
 * @param value - The new numeric value
 */
export function setProperty(
  nodeHash: number,
  key: string,
  value: number
): void {
  ElementaryModule.setProperty(nodeHash, key, value);
}

/**
 * Native renderer for Elementary Audio.
 *
 * Note: Elementary v4 no longer requires a sampleRate argument in the
 * constructor. The sample rate is determined internally by the native
 * audio engine.
 */
export class NativeRenderer extends Renderer {
  constructor() {
    super((instructions: unknown) => {
      ElementaryModule.applyInstructions(JSON.stringify(instructions));
    });
  }
}

export function useRenderer(): { core: Renderer } {
  const ref = useRef<NativeRenderer>();

  if (!ref.current) {
    ref.current = new NativeRenderer();
  }

  return { core: ref.current };
}
