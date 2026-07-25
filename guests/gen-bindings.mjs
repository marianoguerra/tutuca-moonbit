#!/usr/bin/env node
// Regenerate the checked-in MoonBit guest bindings from the canonical WIT.
//
//   node guests/gen-bindings.mjs            # both guests
//   node guests/gen-bindings.mjs counter    # just one
//
// Run it after any change to dyncomp/wit/tutuca-component.wit or a toolchain
// bump, then `git diff` — the trees are checked in, so the diff IS the review.
// `cmd/dev -- gen-guest-bindings` wraps this and follows it with the drift
// check, the same shape as the `gen-views` task.
//
// Three things have to happen for "regenerate, then diff" to mean anything:
//
//   1. wit-bindgen writes `moon.mod.json` / `moon.pkg.json`; this repo keeps
//      the extensionless `moon.mod` / `moon.pkg` (hand-maintained: they carry
//      the `control` import and the warning suppressions). Drop the .json
//      twins rather than let `moon fmt` migrate them over the real ones.
//   2. `moon fmt` owns the layout, exactly as it does for `gen-views` output.
//      It is also what turns the raw shim list into `///|` blocks, which is
//      why it runs BEFORE the sort below.
//   3. wit-bindgen emits the `ffi.mbt` export shims in HASH ORDER, which
//      differs between runs of the same binary on the same input. MoonBit
//      `///|` blocks are order-irrelevant, so we sort them — that is what
//      makes the output reproducible and the drift check honest. A second
//      `moon fmt` then confirms reordering left the file in normal form.
//
// The handwritten files in the generated tree (`sdk.mbt`, `<name>.mbt`) have
// names wit-bindgen never emits, so it leaves them alone; `moon fmt` formats
// them like anything else.
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { GUESTS, WIT_DIR, guestDir } from './guests.mjs';

const wanted = process.argv.slice(2);
const targets = wanted.length ? wanted : GUESTS;
for (const name of targets) {
  if (!GUESTS.includes(name)) {
    console.error(`unknown guest '${name}' — expected one of ${GUESTS.join(', ')}`);
    process.exit(2);
  }
}

/// Every file under `dir`, skipping build output.
function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === '_build' || entry === 'dist' || entry === 'target') continue;
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}

/// Sort a generated module's `///|` blocks. The leading text before the first
/// block (the "DO NOT EDIT" banner and any imports) stays put.
function sortBlocks(source) {
  const marker = '\n///|\n';
  const first = source.indexOf(marker);
  if (first < 0) return source;
  const head = source.slice(0, first + 1);
  const blocks = source
    .slice(first + 1)
    .split('///|\n')
    .filter((b) => b.trim() !== '')
    .map((b) => b.replace(/\s*$/, '\n'));
  blocks.sort();
  return head + blocks.map((b) => `///|\n${b}`).join('\n');
}

for (const name of targets) {
  const dir = guestDir(name);
  console.log(`· wit-bindgen moonbit ${WIT_DIR} -> guests/${name}`);
  execFileSync(
    'wit-bindgen',
    ['moonbit', WIT_DIR, '--out-dir', '.', '--derive-eq', '--derive-show'],
    { stdio: 'inherit', cwd: dir },
  );

  // (1) the .json twins of hand-maintained package files
  for (const path of walk(dir)) {
    if (path.endsWith('moon.pkg.json') || path.endsWith('moon.mod.json')) {
      const extensionless = path.replace(/\.json$/, '');
      try {
        statSync(extensionless);
        rmSync(path);
      } catch {
        // no extensionless sibling: this one IS the package file, keep it
      }
    }
  }

  // (2)
  execFileSync('moon', ['fmt'], { stdio: 'inherit', cwd: dir });

  // (3) hash-ordered generated FFI shims, now that fmt has made them blocks
  for (const path of walk(dir)) {
    if (path.endsWith('ffi.mbt') || path.endsWith('ffi_import.mbt')) {
      const before = readFileSync(path, 'utf8');
      const after = sortBlocks(before);
      if (after !== before) writeFileSync(path, after);
    }
  }
  execFileSync('moon', ['fmt'], { stdio: 'inherit', cwd: dir });
  console.log(`· regenerated guests/${name}`);
}
