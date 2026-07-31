#!/usr/bin/env node
// Build ONE MoonBit `tutuca:component` guest end-to-end:
//   moon build --target wasm  ->  wasm-tools component embed (utf16)
//   ->  wasm-tools component new  ->  jco transpile --instantiation async
// Output: <guest>/dist/<name>.component.wasm + <guest>/dist/js/ (ESM + core wasm).
//
//   node guests/build-guest.mjs counter
//   node guests/build-guest.mjs todo
//
// The guests differ only in their directory and output name, so they share
// this script rather than a copy each. The WIT embedded here is the canonical
// dyncomp/wit/tutuca-component.wit — guests do not keep their own copy, so a
// host and its guests cannot drift apart.
//
// Prereqs (version-coupled; regenerate bindings with gen-bindings.mjs when
// bumping any of them): moon v0.10.x, wit-bindgen-cli 0.59.0,
// wasm-tools 1.244.x, @bytecodealliance/jco (repo devDependency; bare "jco"
// on npm is a dependency-confusion placeholder — never install it).
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

import { GUESTS, WIT_DIR, guestDir, repoRoot } from './guests.mjs';

const name = process.argv[2];
if (!GUESTS.includes(name)) {
  console.error(
    `usage: node guests/build-guest.mjs <${GUESTS.join('|')}>\n` +
      `  (the Rust guest has its own pipeline: guests/rust-notepad/build.mjs)`,
  );
  process.exit(2);
}

const here = guestDir(name);
const dist = join(here, 'dist');
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit', cwd: here });

mkdirSync(dist, { recursive: true });

run('moon', ['build', '--target', 'wasm', '--release']);
run('wasm-tools', [
  'component', 'embed', WIT_DIR,
  join('_build', 'wasm', 'release', 'build', 'gen', 'gen.wasm'),
  '--encoding', 'utf16',
  '-o', join(dist, `${name}.embedded.wasm`),
]);
run('wasm-tools', [
  'component', 'new',
  join(dist, `${name}.embedded.wasm`),
  '-o', join(dist, `${name}.component.wasm`),
]);
run(process.execPath, [
  join(repoRoot, 'node_modules', '@bytecodealliance', 'jco', 'src', 'jco.js'),
  'transpile', join(dist, `${name}.component.wasm`),
  '--instantiation', 'async',
  '-o', join(dist, 'js'),
]);
console.log('built', join(dist, `${name}.component.wasm`), 'and', join(dist, 'js'));
