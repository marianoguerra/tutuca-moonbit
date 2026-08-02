#!/usr/bin/env node
// Build the Rust guest end-to-end:
//   cargo build --release --target wasm32-unknown-unknown
//   -> wasm-tools component new (the wit-bindgen macro embeds the WIT)
//   -> jco transpile --instantiation async
// Output: dist/rust-tempconv.component.wasm + dist/js/.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { jcoBin } from '../guests.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, 'dist');
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit', cwd: here });

mkdirSync(dist, { recursive: true });

run('cargo', ['build', '--release', '--target', 'wasm32-unknown-unknown']);
run('wasm-tools', [
  'component', 'new',
  join('target', 'wasm32-unknown-unknown', 'release', 'rust_tempconv.wasm'),
  '-o', join(dist, 'rust-tempconv.component.wasm'),
]);
run(process.execPath, [
  jcoBin(),
  'transpile', join(dist, 'rust-tempconv.component.wasm'),
  '--instantiation', 'async',
  '-o', join(dist, 'js'),
]);
console.log('built', join(dist, 'rust-tempconv.component.wasm'), 'and', join(dist, 'js'));
