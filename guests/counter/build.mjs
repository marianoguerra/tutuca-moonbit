#!/usr/bin/env node
// Build the counter guest end-to-end:
//   moon build --target wasm  ->  wasm-tools component embed (utf16)
//   ->  wasm-tools component new  ->  jco transpile --instantiation async
// Output: dist/counter.component.wasm + dist/js/ (ESM + core wasm).
//
// Prereqs (version-coupled; regenerate bindings when bumping any of them):
//   moon v0.10.x, wit-bindgen-cli 0.59.0, wasm-tools 1.244.x,
//   @bytecodealliance/jco (repo devDependency; bare "jco" on npm is a
//   dependency-confusion placeholder — never install it).
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
const dist = join(here, 'dist');
const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { stdio: 'inherit', cwd: here, ...opts });

mkdirSync(dist, { recursive: true });

run('moon', ['build', '--target', 'wasm', '--release']);
run('wasm-tools', [
  'component', 'embed', 'wit',
  join('_build', 'wasm', 'release', 'build', 'gen', 'gen.wasm'),
  '--encoding', 'utf16',
  '-o', join(dist, 'counter.embedded.wasm'),
]);
run('wasm-tools', [
  'component', 'new',
  join(dist, 'counter.embedded.wasm'),
  '-o', join(dist, 'counter.component.wasm'),
]);
run(process.execPath, [
  join(repoRoot, 'node_modules', '@bytecodealliance', 'jco', 'src', 'jco.js'),
  'transpile', join(dist, 'counter.component.wasm'),
  '--instantiation', 'async',
  '-o', join(dist, 'js'),
]);
console.log('built', join(dist, 'counter.component.wasm'), 'and', join(dist, 'js'));
