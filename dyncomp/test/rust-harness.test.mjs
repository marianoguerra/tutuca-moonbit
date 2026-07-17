// The polyglot proof: the SAME fake-host protocol that drives the MoonBit
// counter (harness.test.mjs) drives a guest written in Rust with zero
// tutuca code. Build it first:
//   node guests/rust-counter/build.mjs
// then:
//   node --test dyncomp/test/rust-harness.test.mjs
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/rust-counter/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('rust-counter.component.js', jsDir)));

let controlBuf = [];
const control = {
  log: () => {},
  emit: (name, args) => controlBuf.push({ kind: 'emit', name, args }),
  send: (name, args) => controlBuf.push({ kind: 'send', name, args }),
  request: (name, args) => controlBuf.push({ kind: 'request', name, args }),
  makeInstance: () => 0n,
  dropInstance: () => {},
};
const values = {
  listLen: () => 0, listGet: () => ({ tag: 'nil' }),
  mapLen: () => 0, mapKeys: () => [], mapGet: () => undefined,
  listNew: () => 0n, listPush: () => {}, mapNew: () => 0n, mapSet: () => {},
  toJson: () => 'null', fromJson: () => ({ tag: 'nil' }),
};

let guest;
before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('rust-counter.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    'tutuca:component/values@0.1.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.1.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
});

test('rust guest speaks the same contract', { skip: !built }, () => {
  const m = guest.getManifest();
  assert.equal(m.apiVersion, 1);
  assert.equal(m.moduleName, 'rustcounterlib');
  assert.match(m.components[0].views[0].html, /@on\.click="inc"/);

  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 10 }]]);
  const a2 = a.handleEvent('input', 'inc', undefined, []);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 11 });
  assert.deepEqual(a.getField('count'), { tag: 'number', val: 10 });
  assert.deepEqual(a2.callMethod('label', []), { tag: 'text', val: 'rust count is 11' });
  assert.equal(a2.toJson(), '{"count": 11}');

  controlBuf = [];
  assert.equal(a.handleEvent('input', 'double', undefined, []), undefined);
  assert.deepEqual(controlBuf, [
    { kind: 'request', name: 'double', args: [{ tag: 'number', val: 10 }] },
  ]);
  const a3 = a.handleEvent('response', 'double', undefined,
    [{ tag: 'number', val: 20 }, { tag: 'nil' }]);
  assert.deepEqual(a3.getField('count'), { tag: 'number', val: 20 });

  const b = new guest.Instance('Counter', [['count', { tag: 'number', val: 10 }]]);
  assert.equal(a.eq(b), true);
  assert.equal(a.eq(a2), false);
});
