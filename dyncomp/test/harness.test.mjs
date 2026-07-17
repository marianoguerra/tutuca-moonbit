// Node harness for the tutuca:component contract, driven against the
// counter guest (guests/counter). Build it first:
//   node guests/counter/build.mjs
// then:
//   node --test dyncomp/test/
//
// The fake `values` arena here plays the role dyncomp/host will play in
// wasm-gc: compounds are u64 handles into a host-side table, scalars inline.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const jsDir = new URL('../../guests/counter/dist/js/', import.meta.url);

const arena = new Map();
let nextHandle = 1n;
let importCalls = 0;
const put = (obj) => { const h = nextHandle++; arena.set(h, obj); return h; };
const values = {
  listLen: (h) => { importCalls++; return arena.get(h).length >>> 0; },
  listGet: (h, i) => { importCalls++; return arena.get(h)[i]; },
  mapLen: (h) => arena.get(h).size >>> 0,
  mapKeys: (h) => [...arena.get(h).keys()],
  mapGet: (h, k) => arena.get(h).get(k),
  listNew: () => put([]),
  listPush: (h, v) => arena.get(h).push(v),
  mapNew: () => put(new Map()),
  mapSet: (h, k, v) => arena.get(h).set(k, v),
  toJson: (v) => JSON.stringify(v),
  fromJson: (j) => ({ tag: 'text', val: j }),
};
// the control interface: buffers framework calls, and (as the bridge does)
// implements make-instance by re-entrantly constructing guest resources
let controlBuf = [];
const children = new Map(); // token -> Instance
let nextChild = 1;
// The Component Model forbids re-entering a component mid-call, so
// make-instance reserves the token and defers construction until the
// current guest call returns (mirrors the browser bridge).
let pendingChildren = [];
const drainChildren = () => {
  while (pendingChildren.length) {
    const { token, component, args } = pendingChildren.shift();
    children.set(token, new guest.Instance(component, args));
  }
};
const control = {
  log: () => {},
  emit: (name, args) => controlBuf.push({ kind: 'emit', name, args }),
  send: (name, args) => controlBuf.push({ kind: 'send', name, args }),
  request: (name, args) => controlBuf.push({ kind: 'request', name, args }),
  makeInstance: (component, args) => {
    const t = nextChild++;
    pendingChildren.push({ token: t, component, args });
    return BigInt(t);
  },
  dropInstance: (t) => children.delete(Number(t)),
};

let guest;
before(async () => {
  const { instantiate } = await import(new URL('counter.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    // jco emits unversioned import keys today; provide both to be safe.
    'tutuca:component/values@0.1.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.1.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
});

test('manifest declares the component, views, handlers, style', () => {
  const m = guest.getManifest();
  assert.equal(m.apiVersion, 1);
  assert.equal(m.moduleName, 'counterlib');
  assert.deepEqual(m.components.map((c) => c.name), ['Counter', 'Pair']);
  const [comp] = m.components;
  assert.deepEqual(comp.inputHandlers, ['inc', 'dec', 'double']);
  assert.deepEqual(comp.receiveHandlers, ['init', 'sum']);
  assert.deepEqual(comp.responseHandlers, ['double']);
  assert.deepEqual(comp.methodNames, ['label']);
  assert.equal(comp.views[0].name, 'main');
  assert.match(comp.views[0].html, /@on\.click="inc"/);
  assert.match(comp.views[0].html, /@text="\.count"/);
  assert.match(comp.style, /\.counter/);
});

test('instances are independent and constructor args apply', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 10 }]]);
  const b = new guest.Instance('Counter', []);
  assert.deepEqual(a.getField('count'), { tag: 'number', val: 10 });
  assert.deepEqual(b.getField('count'), { tag: 'number', val: 0 });
  assert.equal(a.getField('nope'), undefined);
});

test('handle-event is functional: new instance out, old unchanged', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 10 }]]);
  const a2 = a.handleEvent('input', 'inc', undefined, []);
  assert.ok(a2 instanceof guest.Instance);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 11 });
  assert.deepEqual(a.getField('count'), { tag: 'number', val: 10 });
  assert.equal(a.handleEvent('input', 'unknown', undefined, []), undefined);
  assert.equal(a.handleEvent('receive', 'init', undefined, []), undefined);
});

test('eq and to-json project the opaque state', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 5 }]]);
  const b = new guest.Instance('Counter', [['count', { tag: 'number', val: 5 }]]);
  const c = a.handleEvent('input', 'inc', undefined, []);
  assert.equal(a.eq(b), true);
  assert.equal(a.eq(c), false);
  assert.equal(c.toJson(), '{"count": 6, "history": [5]}');
});

test('history crosses as an arena list; label is a callable method', () => {
  const a = new guest.Instance('Counter', []);
  const a1 = a.handleEvent('input', 'inc', undefined, []);
  const a2 = a1.handleEvent('input', 'inc', undefined, []);
  const hist = a2.getField('history');
  assert.equal(hist.tag, 'list');
  assert.deepEqual(arena.get(hist.val).map((v) => v.val), [0, 1]);
  assert.deepEqual(a2.callMethod('label', []), { tag: 'text', val: 'count is 2' });
});

test('input "double" buffers a control request; the response applies it', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 21 }]]);
  controlBuf = [];
  assert.equal(a.handleEvent('input', 'double', undefined, []), undefined);
  assert.equal(controlBuf.length, 1);
  assert.equal(controlBuf[0].kind, 'request');
  assert.equal(controlBuf[0].name, 'double');
  assert.deepEqual(controlBuf[0].args[0], { tag: 'number', val: 21 });
  // host resolves the request and dispatches the response bucket
  const a2 = a.handleEvent('response', 'double', undefined,
    [{ tag: 'number', val: 42 }, { tag: 'nil' }]);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 42 });
});

test('Pair creates children via control.make-instance and exposes tokens', () => {
  const before = children.size;
  const p = new guest.Instance('Pair', []);
  drainChildren();
  assert.equal(children.size, before + 2);
  const left = p.getField('left');
  const right = p.getField('right');
  assert.equal(left.tag, 'instance');
  assert.equal(right.tag, 'instance');
  assert.deepEqual(children.get(Number(left.val)).getField('count'),
    { tag: 'number', val: 1 });
  assert.deepEqual(children.get(Number(right.val)).getField('count'),
    { tag: 'number', val: 100 });
  // with-field swaps a child token functionally
  const t = control.makeInstance('Counter', [['count', { tag: 'number', val: 7 }]]);
  drainChildren();
  const p2 = p.withField('left', { tag: 'instance', val: t });
  assert.deepEqual(p2.getField('left'), { tag: 'instance', val: t });
  assert.deepEqual(p.getField('left'), left); // original unchanged
});

test('with-field returns a successor for known fields only', () => {
  const a = new guest.Instance('Counter', []);
  const a9 = a.withField('count', { tag: 'number', val: 9 });
  assert.deepEqual(a9.getField('count'), { tag: 'number', val: 9 });
  assert.equal(a.withField('other', { tag: 'nil' }), undefined);
});

test('guest reads host arena compounds mid-dispatch (re-entrancy)', () => {
  const b = new guest.Instance('Counter', []);
  const list = put([
    { tag: 'number', val: 1 },
    { tag: 'number', val: 2 },
    { tag: 'number', val: 39 },
  ]);
  importCalls = 0;
  const summed = b.handleEvent('receive', 'sum', undefined, [{ tag: 'list', val: list }]);
  assert.deepEqual(summed.getField('count'), { tag: 'number', val: 42 });
  assert.equal(importCalls, 4); // 1 list-len + 3 list-get
});
