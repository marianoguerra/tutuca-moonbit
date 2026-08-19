// The host-owned canonical ABI must agree with generated component bindings.
// This test bypasses jco entirely and loads the one core wasm a v0.6 archive
// actually ships.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { instantiate } from '../host/wasm/abi.mjs';

const jsDir = new URL('../../guests/counter/dist/js/', import.meta.url);

test('host ABI loads a core-only v0.6 guest and preserves event results', async () => {
  const arena = new Map();
  let next = 1n;
  const put = (value) => {
    const handle = next++;
    arena.set(handle, value);
    return handle;
  };
  const values = {
    listLen: (h) => arena.get(h).length,
    listGet: (h, i) => arena.get(h)[i],
    mapLen: (h) => arena.get(h).size,
    mapKeys: (h) => [...arena.get(h).keys()],
    mapGet: (h, k) => arena.get(h).get(k),
    listNew: () => put([]),
    listPush: (h, value) => arena.get(h).push(value),
    mapNew: () => put(new Map()),
    mapSet: (h, key, value) => arena.get(h).set(key, value),
    toJson: JSON.stringify,
    fromJson: JSON.parse,
  };
  const control = {
    log: () => {}, emit: () => {}, send: () => {}, sendAt: () => {},
    bubbleAt: () => {}, stopPropagation: () => {}, request: () => {},
    after: () => {}, makeInstance: () => 0n, dropInstance: () => {},
  };
  const root = await instantiate(
    async (name) => WebAssembly.compile(await readFile(new URL(name, jsDir))),
    {
      'tutuca:component/values': values,
      'tutuca:component/control': control,
    },
    {
      world: 'tutuca:component@0.8.0',
      encoding: 'utf16',
      core: 'counter.component.core.wasm',
    },
  );

  const counter = new root.guest.Instance('Counter', [
    ['count', { tag: 'number', val: 4 }],
  ]);
  assert.deepEqual(counter.handleEvent('input', 'unknown', []), { tag: 'unhandled' });
  assert.deepEqual(counter.handleEvent('receive', 'init', []), { tag: 'unchanged' });
  const changed = counter.handleEvent('input', 'inc', []);
  assert.equal(changed.tag, 'changed');
  assert.deepEqual(changed.val.getField('count'), { tag: 'number', val: 5 });
  assert.equal(root.guest.getManifest, undefined);
});

// A bundle built against an OLDER world still binds.
//
// The release promises it — a `.tutuca.tar.gz` compiled against
// `tutuca:component@0.7.0` keeps loading with no rebuild — and until this test
// the promise rested on reading `abi.mjs` rather than on running it. The module
// here is hand-assembled rather than a real guest because the property under
// test is the IMPORT BINDING and nothing else: `unversioned()` strips the
// version off the module name before the lookup, and `IMPL_VERSIONS` lets a
// host key its table either way.
//
// Built from WAT at test time so the fixture is readable in the diff.
test('a module importing the 0.7.0 world binds against this host', async () => {
  const { execFileSync } = await import('node:child_process');
  const { mkdtempSync, writeFileSync, readFileSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');

  const dir = mkdtempSync(join(tmpdir(), 'tutuca-abi-'));
  try {
    const wat = join(dir, 'old.wat');
    const wasm = join(dir, 'old.wasm');
    writeFileSync(wat, `(module
  (import "tutuca:component/control@0.7.0" "request"
    (func $req (param i32 i32 i32 i32 i32)))
  (import "tutuca:component/control@0.7.0" "send"
    (func $send (param i32 i32 i32 i32)))
  (import "tutuca:component/values@0.7.0" "to-json"
    (func $tj (param i32 i64 i32)))
  (memory (export "memory") 1)
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32) i32.const 0)
)`);
    try {
      execFileSync('wasm-tools', ['parse', wat, '-o', wasm], { stdio: 'pipe' });
    } catch {
      // wasm-tools is what the whole guest suite needs; without it there is
      // nothing to assemble and nothing to assert.
      return;
    }

    // The host keys its tables WITHOUT a version, which is the spelling this
    // test is about: the bundle says 0.7.0 and the host says nothing.
    const seen = [];
    const control = {
      log: () => {}, emit: () => {}, send: () => seen.push('send'),
      sendAt: () => {}, bubbleAt: () => {}, stopPropagation: () => {},
      request: () => seen.push('request'),
      intent: () => {}, intentAt: () => {}, forward: () => {},
      reply: () => {}, fail: () => {},
      after: () => {}, makeInstance: () => 0n, dropInstance: () => {},
    };
    const values = {
      listLen: () => 0, listGet: () => null, mapLen: () => 0, mapKeys: () => [],
      mapGet: () => undefined, listNew: () => 0n, listPush: () => {},
      mapNew: () => 0n, mapSet: () => {},
      toJson: JSON.stringify, fromJson: JSON.parse,
    };

    // No `guest` export on this module, so `instantiate` cannot build the
    // facade — what is asserted is that binding got that far without refusing
    // an import, which is the whole of the compatibility claim.
    let err = null;
    try {
      await instantiate(
        async () => WebAssembly.compile(readFileSync(wasm)),
        { 'tutuca:component/values': values, 'tutuca:component/control': control },
        { world: 'tutuca:component@0.8.0', encoding: 'utf16', core: 'old.wasm' },
      );
    } catch (e) {
      err = e;
    }
    if (err) {
      assert.doesNotMatch(
        err.message,
        /outside tutuca:component|does not implement/,
        `a 0.7.0 import was refused: ${err.message}`,
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
