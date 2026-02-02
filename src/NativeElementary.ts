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

  addListener(eventName: string): void;
  removeListeners(count: number): void;

  // VFS methods
  loadAudioResource(key: string, filePath: string): Promise<AudioResourceInfo>;
  unloadAudioResource(key: string): Promise<boolean>;

  // Path helpers
  getDocumentsDirectory(): Promise<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Elementary');
