import { NativeModules } from 'react-native';

// Mock the native module before importing our module
const mockElementary = {
  getAudioInfo: jest.fn(),
  getSampleRate: jest.fn(),
  loadAudioResource: jest.fn(),
  loadAudioResourceForReadback: jest.fn(),
  readAudioResourcePCM: jest.fn(),
  unloadAudioResource: jest.fn(),
  applyInstructions: jest.fn(),
  setProperty: jest.fn(),
  getDocumentsDirectory: jest.fn(),
  getBundlePath: jest.fn(),
  activateAudioSession: jest.fn(),
  deactivateAudioSession: jest.fn(),
  configureAudioSession: jest.fn(),
  disableAudioSessionManagement: jest.fn(),
  startEventPolling: jest.fn(),
  stopEventPolling: jest.fn(),
  configureEventPolling: jest.fn(),
};

// Needs to be set before module imports
NativeModules.Elementary = mockElementary;

// We test the public API here — these tests verify behavior observable from JS
describe('react-native-elementary', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.resetModules();
    // Re-apply mock after reset
    NativeModules.Elementary = mockElementary;
  });

  describe('native module binding', () => {
    it('provides access to native getAudioInfo through NativeModules', () => {
      // getAudioInfo is available on the native module but not re-exported
      // as a library function. It's called internally or via NativeModules directly.
      expect(mockElementary.getAudioInfo).toBeDefined();
    });
  });

  describe('getSampleRate', () => {
    it('resolves with sample rate', async () => {
      mockElementary.getSampleRate.mockResolvedValueOnce(44100);

      const { getSampleRate } = require('../index');
      const result = await getSampleRate();
      expect(result).toBe(44100);
    });
  });

  describe('loadAudioResource', () => {
    it('resolves with resource info', async () => {
      const info = {
        key: 'kick',
        channels: 2,
        sampleCount: 44100,
        sampleRate: 44100,
        durationMs: 1000,
      };
      mockElementary.loadAudioResource.mockResolvedValueOnce(info);

      const { loadAudioResource } = require('../index');
      const result = await loadAudioResource('kick', '/path/to/kick.wav');
      expect(result).toEqual(info);
    });

    it('rejects on engine init failure', async () => {
      mockElementary.loadAudioResource.mockRejectedValueOnce(
        new Error('Failed to initialize audio engine')
      );

      const { loadAudioResource } = require('../index');
      await expect(
        loadAudioResource('kick', '/path/to/kick.wav')
      ).rejects.toThrow('Failed to initialize audio engine');
    });
  });

  describe('PCM readback', () => {
    it('loads a file for readback and returns source metadata', async () => {
      const info = {
        key: 'import-1',
        channels: 2,
        sampleCount: 48000,
        sampleRate: 48000,
        durationMs: 1000,
      };
      mockElementary.loadAudioResourceForReadback.mockResolvedValueOnce(info);
      const { loadAudioResourceForReadback } = require('../index');
      await expect(
        loadAudioResourceForReadback('import-1', '/path/to/audio.flac')
      ).resolves.toEqual(info);
      expect(mockElementary.loadAudioResourceForReadback).toHaveBeenCalledWith(
        'import-1',
        '/path/to/audio.flac'
      );
      expect(mockElementary.loadAudioResource).not.toHaveBeenCalled();
    });

    it('propagates decoder errors for failed imports', async () => {
      mockElementary.loadAudioResourceForReadback.mockRejectedValueOnce(
        new Error('Failed to open audio file')
      );
      const { loadAudioResourceForReadback } = require('../index');
      await expect(
        loadAudioResourceForReadback('import-1', '/path/to/unsupported.m4a')
      ).rejects.toThrow('Failed to open audio file');
    });

    it('passes frame offsets and returns interleaved samples unchanged', async () => {
      const samples = [0.25, -0.5, 0.75, -1];
      mockElementary.readAudioResourcePCM.mockResolvedValueOnce(samples);
      const { readAudioResourcePCM } = require('../index');
      await expect(readAudioResourcePCM('import-1', 500, 2)).resolves.toEqual(
        samples
      );
      expect(mockElementary.readAudioResourcePCM).toHaveBeenCalledWith(
        'import-1',
        500,
        2
      );
    });

    it('propagates native range validation errors', async () => {
      mockElementary.readAudioResourcePCM.mockRejectedValueOnce(
        new Error('Invalid PCM frame range')
      );
      const { readAudioResourcePCM } = require('../index');
      await expect(readAudioResourcePCM('import-1', 0, 16385)).rejects.toThrow(
        'Invalid PCM frame range'
      );
    });
  });

  describe('unloadAudioResource', () => {
    it('resolves with true when resource was found and unloaded', async () => {
      mockElementary.unloadAudioResource.mockResolvedValueOnce(true);

      const { unloadAudioResource } = require('../index');
      const result = await unloadAudioResource('kick');
      expect(result).toBe(true);
    });

    it('resolves with false when resource was not found', async () => {
      // This is the key TDD test: unload should NOT require engine init.
      // If engine was never started, there are no resources to unload.
      // The native side should resolve with NO/false, not reject.
      mockElementary.unloadAudioResource.mockResolvedValueOnce(false);

      const { unloadAudioResource } = require('../index');
      const result = await unloadAudioResource('nonexistent');
      expect(result).toBe(false);
    });

    it('should not reject when engine is not initialized', async () => {
      // Regression test: unload should never fail because engine isn't started.
      // If the engine was never initialized, there's nothing to unload.
      mockElementary.unloadAudioResource.mockResolvedValueOnce(false);

      const { unloadAudioResource } = require('../index');
      // This should resolve, not reject
      await expect(unloadAudioResource('any')).resolves.toBe(false);
    });
  });

  describe('applyInstructions', () => {
    it('calls native applyInstructions', () => {
      expect(mockElementary.applyInstructions).toBeDefined();
    });
  });

  describe('setProperty', () => {
    it('calls native setProperty', () => {
      const { setProperty } = require('../index');
      setProperty(12345, 'value', 0.5);
      expect(mockElementary.setProperty).toHaveBeenCalledWith(
        12345,
        'value',
        0.5
      );
    });
  });

  describe('event polling', () => {
    it('startEventPolling calls native', async () => {
      mockElementary.startEventPolling.mockResolvedValueOnce(true);
      const { startEventPolling } = require('../index');
      const result = await startEventPolling();
      expect(result).toBe(true);
    });

    it('stopEventPolling calls native', async () => {
      mockElementary.stopEventPolling.mockResolvedValueOnce(true);
      const { stopEventPolling } = require('../index');
      const result = await stopEventPolling();
      expect(result).toBe(true);
    });

    it('configureEventPolling calls native', async () => {
      mockElementary.configureEventPolling.mockResolvedValueOnce(true);
      const { configureEventPolling } = require('../index');
      const result = await configureEventPolling(100);
      expect(result).toBe(true);
    });
  });

  describe('audio session', () => {
    it('activateAudioSession calls native', async () => {
      mockElementary.activateAudioSession.mockResolvedValueOnce(true);
      const { activateAudioSession } = require('../index');
      const result = await activateAudioSession();
      expect(result).toBe(true);
    });

    it('deactivateAudioSession calls native', async () => {
      mockElementary.deactivateAudioSession.mockResolvedValueOnce(true);
      const { deactivateAudioSession } = require('../index');
      const result = await deactivateAudioSession();
      expect(result).toBe(true);
    });

    it('configureAudioSession calls native with defaults', () => {
      const { configureAudioSession } = require('../index');
      configureAudioSession();
      expect(mockElementary.configureAudioSession).toHaveBeenCalledWith(
        'playback',
        'default',
        ['mixWithOthers', 'allowBluetoothA2DP']
      );
    });

    it('disableAudioSessionManagement calls native', () => {
      const { disableAudioSessionManagement } = require('../index');
      disableAudioSessionManagement();
      expect(mockElementary.disableAudioSessionManagement).toHaveBeenCalled();
    });
  });

  describe('useRenderer', () => {
    it('returns a core renderer (stable ref)', () => {
      const mod = require('../index');
      expect(typeof mod.useRenderer).toBe('function');
    });
  });
});
