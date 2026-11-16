import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(
  path.resolve(__dirname, '../../ios/Elementary.mm'),
  'utf8'
);

describe('iOS render buffer safety', () => {
  it('only gives Elementary the output buffers supplied to the render callback', () => {
    expect(source).not.toContain(
      'for (UInt8 channel = 0; channel < numOutputChannels; channel++)'
    );
    expect(source).toContain(
      'MIN(suppliedBufferCount, (UInt32)numOutputChannels)'
    );
    expect(source).toContain(
      'outputBuffer->data(), actualChannels, frameCount'
    );
    expect(source).toContain(
      'frameCount > buffer.mDataByteSize / sizeof(float)'
    );
    expect(source).toContain('blockOutput, blockChannels, blockSize, nullptr');
  });

  it('keeps every replaceable runtime pointer access behind the mutex', () => {
    const method = (start: string, end: string) =>
      source.slice(
        source.indexOf(start),
        source.indexOf(end, source.indexOf(start))
      );
    const methods = [
      method(
        'RCT_EXPORT_METHOD(getAudioInfo:',
        '#pragma mark - React Native Methods'
      ),
      method('- (void)setProperty:', '- (void)getSampleRate:'),
      method('- (void)loadAudioResource:', '- (void)unloadAudioResource:'),
      method('- (void)unloadAudioResource:', '- (void)getDocumentsDirectory:'),
    ];

    expect(source).not.toContain(
      'self.audioEngineInitialized && self.runtime != nullptr'
    );
    expect(source).not.toContain(
      'initializeAudioEngineIfNeeded] || self.runtime == nullptr'
    );
    for (const body of methods) {
      expect(
        body.indexOf('std::lock_guard<std::mutex>')
      ).toBeGreaterThanOrEqual(0);
      expect(body.indexOf('self.runtime')).toBeGreaterThan(
        body.indexOf('std::lock_guard<std::mutex>')
      );
    }
  });

  it('serializes runtime replacement before route callbacks resume', () => {
    expect(source).toMatch(
      /Runtime fixed block size[\s\S]*?lock\(_runtimeMutex\);[\s\S]*?self\.runtime =/
    );
    expect(source).toMatch(
      /dispatch_source_set_event_handler[\s\S]*?pollRuntimeEvents\(strongSelf->_runtimeMutex,[\s\S]*?return strongSelf\.runtime;/
    );

    const initializerStart = source.indexOf(
      '- (BOOL)initializeAudioEngineIfNeeded'
    );
    const initializerEnd = source.indexOf(
      '- (void)startEventPolling',
      initializerStart
    );
    const initializer = source.slice(initializerStart, initializerEnd);
    const initialRuntime = initializer.indexOf(
      'self.runtime = std::make_shared'
    );
    const initialEngineStart = initializer.indexOf('startAndReturnError');
    expect(initialRuntime).toBeGreaterThanOrEqual(0);
    expect(initialEngineStart).toBeGreaterThanOrEqual(0);
    expect(initialRuntime).toBeLessThan(initialEngineStart);

    const handlerStart = source.indexOf('- (void)handleEngineConfigChange:');
    const handlerEnd = source.indexOf(
      '+ (BOOL) requiresMainQueueSetup',
      handlerStart
    );
    const handler = source.slice(handlerStart, handlerEnd);
    const replacementRuntime = handler.indexOf(
      'strongSelf.runtime = std::make_shared'
    );
    const replacementEngineStart = handler.indexOf('startAndReturnError');
    expect(replacementRuntime).toBeGreaterThanOrEqual(0);
    expect(replacementEngineStart).toBeGreaterThanOrEqual(0);
    expect(replacementRuntime).toBeLessThan(replacementEngineStart);
  });
});
