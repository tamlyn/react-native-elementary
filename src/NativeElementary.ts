import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

// Custom type for audio resource metadata
export type AudioResourceInfo = {
  key: string;
  channels: number;
  sampleCount: number;
  sampleRate: number;
  durationMs: number;
};

export interface Spec extends TurboModule {
  getSampleRate(): Promise<number>;
  applyInstructions(message: string): void;

  // Real-time property updates (no graph re-render, audio-thread safe)
  // nodeHash is the elem node hash (int32), key is the property name, value is the new value
  setProperty(nodeHash: number, key: string, value: number): void;

  addListener(eventName: string): void;
  removeListeners(count: number): void;

  // VFS methods
  loadAudioResource(key: string, filePath: string): Promise<AudioResourceInfo>;
  unloadAudioResource(key: string): Promise<boolean>;

  // Path helpers
  getDocumentsDirectory(): Promise<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Elementary');
