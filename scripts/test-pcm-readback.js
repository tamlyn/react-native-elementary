const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const temporary = mkdtempSync(path.join(tmpdir(), 'elementary-readback-'));

try {
  const executable = path.join(temporary, 'pcm-readback-tests');
  execFileSync(
    process.env.CXX || 'clang++',
    [
      '-std=c++17',
      '-pthread',
      '-fsanitize=address,undefined',
      '-fno-omit-frame-pointer',
      path.join(root, 'cpp/tests/PCMReadbackTests.cpp'),
      path.join(root, 'cpp/AudioResourceLoader.cpp'),
      '-o',
      executable,
    ],
    { stdio: 'inherit' }
  );
  execFileSync(executable, [path.join(root, 'cpp/__fixtures__'), temporary], {
    stdio: 'inherit',
  });
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
