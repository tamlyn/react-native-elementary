import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(
  path.resolve(__dirname, '../../ios/Elementary.mm'),
  'utf8'
);

describe('iOS Simulator audio route priming', () => {
  it('uses an explicitly muted, valid PCM silence buffer', () => {
    const declaration = source.match(
      /kSimulatorRoutePrimerWav\[(\d+)\]\s*=\s*\{([\s\S]*?)\};/
    );
    expect(declaration).not.toBeNull();
    if (!declaration?.[1] || !declaration[2]) throw new Error('Missing WAV');

    const length = Number(declaration[1]);
    const initializedBytes = Array.from(
      declaration[2].matchAll(/0x([\da-f]{2})/gi),
      (match) => Number.parseInt(match[1] ?? '', 16)
    );
    const wav = Buffer.alloc(length);
    initializedBytes.forEach((byte, index) => {
      wav[index] = byte;
    });

    expect(wav.toString('ascii', 0, 4)).toBe('RIFF');
    expect(wav.readUInt32LE(4)).toBe(length - 8);
    expect(wav.toString('ascii', 8, 12)).toBe('WAVE');
    expect(wav.readUInt16LE(20)).toBe(1); // PCM
    expect(wav.readUInt16LE(22)).toBe(2); // stereo
    expect(wav.readUInt32LE(24)).toBe(44_100);
    expect(wav.readUInt16LE(34)).toBe(16);
    expect(wav.readUInt32LE(40)).toBe(length - 44);
    expect(wav.subarray(44).every((sample) => sample === 0)).toBe(true);
    expect(source).toContain('player.volume = 0.0f');
  });

  it('holds the muted route open while the shared AVAudioEngine initializes', () => {
    const initializer = source.slice(
      source.indexOf('- (BOOL)initializeAudioEngineIfNeeded'),
      source.indexOf('- (void)startEventPolling')
    );

    expect(source).toContain('#if TARGET_OS_SIMULATOR');
    expect(source).toContain('AVAudioPlayer');
    expect(source).toContain('numberOfLoops = -1');
    expect(source).not.toContain(
      'if (!self.shouldManageAudioSession) return nil;'
    );
    expect(initializer).toContain('if (!routePrimer) return NO;');
    expect(initializer).toMatch(
      /if \(!\[self setAudioSessionActive:YES error:&sessionError\]\) \{[\s\S]*?return NO;/
    );

    const primerStart = initializer.indexOf(
      '[self startSimulatorAudioRoutePrimer]'
    );
    const engineAllocation = initializer.indexOf(
      '[[AVAudioEngine alloc] init]'
    );
    const engineStart = initializer.indexOf('startAndReturnError');
    const primerStops = initializer.match(/\[routePrimer stop\]/g) ?? [];
    const primerStop = initializer.indexOf('[routePrimer stop]');
    expect(primerStart).toBeGreaterThanOrEqual(0);
    expect(engineAllocation).toBeGreaterThanOrEqual(0);
    expect(engineStart).toBeGreaterThanOrEqual(0);
    expect(primerStop).toBeGreaterThanOrEqual(0);
    expect(primerStops).toHaveLength(2);
    expect(primerStart).toBeLessThan(engineAllocation);
    expect(primerStop).toBeGreaterThan(engineStart);
  });
});
