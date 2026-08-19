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
