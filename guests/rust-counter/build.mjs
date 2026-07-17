#!/usr/bin/env node
// Build the Rust guest end-to-end:
//   cargo build --release --target wasm32-unknown-unknown
//   -> wasm-tools component new (the wit-bindgen macro embeds the WIT)
//   -> jco transpile --instantiation async
// Output: dist/rust-counter.component.wasm + dist/js/.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
const dist = join(here, 'dist');
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit', cwd: here });

mkdirSync(dist, { recursive: true });

run('cargo', ['build', '--release', '--target', 'wasm32-unknown-unknown']);
run('wasm-tools', [
  'component', 'new',
  join('target', 'wasm32-unknown-unknown', 'release', 'rust_counter.wasm'),
  '-o', join(dist, 'rust-counter.component.wasm'),
]);
run(process.execPath, [
  join(repoRoot, 'node_modules', '@bytecodealliance', 'jco', 'src', 'jco.js'),
  'transpile', join(dist, 'rust-counter.component.wasm'),
  '--instantiation', 'async',
  '-o', join(dist, 'js'),
]);
console.log('built', join(dist, 'rust-counter.component.wasm'), 'and', join(dist, 'js'));
