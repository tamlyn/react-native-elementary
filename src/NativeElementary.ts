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
  activateAudioSession(): Promise<boolean>;
  deactivateAudioSession(): Promise<boolean>;
  configureAudioSession(
    category: string,
    mode: string,
    options: string[]
  ): void;
  disableAudioSessionManagement(): void;
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
  getBundlePath(): Promise<string>;

  // Event polling control
  // Start/stop polling for el.snapshot, el.meter, el.scope, el.fft events.
  // Polling is NOT started automatically — consumers must opt in.
  // Use configureEventPolling to change the poll interval before starting.
  startEventPolling(): Promise<boolean>;
  stopEventPolling(): Promise<boolean>;
  configureEventPolling(intervalMs: number): Promise<boolean>;

  // iOS audio session (no-ops on Android)
  activateAudioSession(): Promise<boolean>;
  deactivateAudioSession(): Promise<boolean>;
  configureAudioSession(category: string, mode: string, options: any[]): void;
  disableAudioSessionManagement(): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Elementary');
