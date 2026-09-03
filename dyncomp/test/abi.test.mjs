// The host-owned canonical ABI must agree with generated component bindings.
// This test bypasses jco entirely and loads the one core wasm an archive
// actually ships — which is the path `tutucard`'s compiled cards take, and the
// reason this lifter exists beside jco rather than behind it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { instantiate } from '../host/wasm/abi.mjs';

const jsDir = new URL('../../guests/counter/dist/js/', import.meta.url);

test('host ABI loads a core-only guest and preserves event results', async () => {
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
    log: () => {}, send: () => {}, sendAt: () => {},
    intent: () => {}, intentAt: () => {}, forward: () => {},
    reply: () => {}, fail: () => {}, stopPropagation: () => {},
    // 0.12.0: fixed handler/render operations and public properties.
    // no ancestor has nothing to answer with, so nil is the truth here.
    sendReply: () => {}, lookup: () => ({ tag: 'nil' }),
    after: () => {}, makeInstance: () => 0n, dropInstance: () => {},
  };
  const root = await instantiate(
    async (name) => WebAssembly.compile(await readFile(new URL(name, jsDir))),
    {
      'tutuca:component/values': values,
      'tutuca:component/control': control,
    },
    {
      world: 'tutuca:component@0.12.0',
      encoding: 'utf16',
      core: 'counter.component.core.wasm',
    },
  );

  const counter = new root.guest.Instance('Counter', [
    ['count', { tag: 'number', val: 4 }],
  ]);
  assert.deepEqual(counter.handleMessage('unknown', []), { tag: 'unhandled' });
  assert.deepEqual(counter.handleMessage('init', []), { tag: 'unchanged' });
  const changed = counter.handleMessage('inc', []);
  assert.equal(changed.tag, 'changed');
  assert.deepEqual(changed.val.getField('count'), { tag: 'number', val: 5 });
  assert.deepEqual(counter.getProperty('count'), { tag: 'number', val: 4 });
  const propertyChanged = counter.setProperty('count', { tag: 'number', val: 9 });
  assert.equal(propertyChanged.tag, 'changed');
  assert.deepEqual(propertyChanged.val.getProperty('count'), { tag: 'number', val: 9 });
  assert.deepEqual(counter.setProperty('count', { tag: 'text', val: 'bad' }), {
    tag: 'refused',
  });
  assert.deepEqual(counter.setProperty('private', { tag: 'number', val: 1 }), {
    tag: 'missing',
  });
  assert.equal(root.guest.getManifest, undefined);
});
