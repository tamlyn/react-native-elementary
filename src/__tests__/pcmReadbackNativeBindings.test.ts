import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(
  path.resolve(__dirname, '../../ios/Elementary.mm'),
  'utf8'
);

it('decodes iOS readback imports without initializing the live audio engine', () => {
  const start = source.indexOf('- (void)loadAudioResourceForReadback:');
  const end = source.indexOf('- (void)loadResource:', start);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  const readback = source.slice(start, end);
  expect(readback).toContain(
    'AudioResourceLoader::loadFile(keyStr, filePathStr, true)'
  );
  expect(readback).toContain('self->_pcmReadback.put');
  expect(readback).not.toContain('dispatchMainWithEngineInit');
  expect(readback).not.toContain('initializeAudioEngineIfNeeded');
  expect(readback).not.toContain('self.audioEngine');
});

it('releases readback data even if iOS playback was never initialized', () => {
  const unload = source.slice(source.indexOf('- (void)unloadAudioResource:'));
  const erase = unload.indexOf('_pcmReadback.erase');
  const coldReturn = unload.indexOf('if (!self.audioEngineInitialized)');
  expect(erase).toBeGreaterThanOrEqual(0);
  expect(coldReturn).toBeGreaterThan(erase);
  expect(unload.slice(coldReturn)).toContain('resolve(@(removedReadback))');
});
