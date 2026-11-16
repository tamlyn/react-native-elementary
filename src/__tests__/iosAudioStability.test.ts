import fs from 'node:fs';
import path from 'node:path';

const source = fs.readFileSync(
  path.resolve(__dirname, '../../ios/Elementary.mm'),
  'utf8'
);

it('rejects invalid output formats before connecting or replacing the runtime', () => {
  expect(source).toContain('std::isfinite(format.sampleRate)');
  const initializer = source.slice(
    source.indexOf('- (BOOL)initializeAudioEngineIfNeeded'),
    source.indexOf('- (void)startEventPolling')
  );
  expect(
    initializer.indexOf('hasUsableOutputFormat:outputFormat')
  ).toBeLessThan(initializer.indexOf('connect:sourceNode'));
  const route = source.slice(
    source.indexOf('- (void)handleEngineConfigChange:')
  );
  expect(route.indexOf('hasUsableOutputFormat:newFormat')).toBeLessThan(
    route.indexOf('strongSelf.runtime =')
  );
});

it('does not initialize the audio engine to report diagnostics', () => {
  const diagnostics = source.slice(
    source.indexOf('RCT_EXPORT_METHOD(getAudioInfo:'),
    source.indexOf('#pragma mark - React Native Methods')
  );
  expect(diagnostics).not.toContain('dispatchMainWithEngineInit');
  expect(diagnostics).toContain('if (!self.audioEngineInitialized');
  expect(diagnostics).toContain('@"runtimeReady": @NO');
});
