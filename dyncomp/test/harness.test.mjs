// Node harness for the tutuca:component contract, driven against the
// counter guest (guests/counter). Build it first:
//   node guests/counter/build.mjs
// then:
//   node --test 'dyncomp/test/*.test.mjs'
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
  sendAt: (path, name, args) => controlBuf.push({ kind: 'sendAt', path, name, args }),
  bubbleAt: (path, name, args) => controlBuf.push({ kind: 'bubbleAt', path, name, args }),
  stopPropagation: () => controlBuf.push({ kind: 'stopPropagation' }),
  request: (name, args, opts) => controlBuf.push({ kind: 'request', name, args, opts }),
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
    'tutuca:component/values@0.5.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.5.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
});

test('manifest declares the component, its views and its state', () => {
  const m = guest.getManifest();
  assert.equal(m.apiVersion, 5);
  assert.equal(m.moduleName, 'counterlib');
  assert.deepEqual(m.components.map((c) => c.name), ['Counter', 'Pair']);
  const [comp] = m.components;
  // the declared schema: fields over a flat type table (WIT has no recursion),
  // each field carrying the half a type cannot state
  assert.deepEqual(comp.fields.map((f) => [f.name, f.ty]), [['count', 0], ['history', 1]]);
  assert.equal(comp.fields[0].doc, 'The current value.');
  assert.equal(comp.fields[0].required, false);
  assert.equal(comp.fields[0].constraint.min, -1000);
  assert.equal(comp.fields[0].constraint.max, 1000);
  // "" is the contract's spelling for "not stated"
  assert.equal(comp.fields[0].constraint.format, '');
  assert.equal(comp.fields[1].constraint, undefined);
  assert.equal(comp.types[0].kind, 'ty-float');
  assert.equal(comp.types[1].kind, 'ty-list');
  assert.equal(comp.types[1].elem, 0);
  assert.deepEqual(comp.handlers, ['inc', 'dec', 'double', 'triple', 'announce']);
  assert.deepEqual(comp.receives, ['init', 'sum']);
  assert.deepEqual(comp.bubbles, []);
  assert.deepEqual(comp.responses, ['doubled', 'triple']);
  assert.deepEqual(comp.methods, ['label']);
  assert.deepEqual(comp.whens, ['nonZero']);
  // this component serves no requests; the Pair declares the bundle's one
  assert.deepEqual(comp.requests, []);
  assert.deepEqual(m.components[1].requests, ['triple']);
  // input handler names are NOT declared: the host reads them off the views
  assert.equal(comp.inputHandlers, undefined);
  assert.equal(comp.views[0].name, 'main');
  assert.match(comp.views[0].html, /@on\.click="inc"/);
  assert.match(comp.views[0].html, /@text="\.count"/);
  // the guests carry no CSS of their own any more — the views style
  // themselves with margaui utility classes (the universal-wasm commit), which
  // is also what the host's strictest style tier requires
  assert.equal(comp.style, '');
});

test('the manifest carries what a catalog and a model read', () => {
  const m = guest.getManifest();
  assert.match(m.doc, /reference bundle/);
  assert.equal(m.version, '0.4.0');
  // this bundle needs no clock, no randomness and no timer, so it asks for
  // nothing — which is what makes it trivially safe to mount from anywhere
  assert.deepEqual(m.capabilities, []);
  const [comp] = m.components;
  assert.match(comp.doc, /buttons that raise and lower it/);
  assert.ok(comp.keywords.includes('tally'));
  assert.equal(comp.category, 'input');
  // one flat table the host merges by name over the six bucket lists
  const docs = Object.fromEntries(comp.messageDocs.map((d) => [d.name, d.doc]));
  assert.equal(docs.inc, 'Add one.');
  assert.equal(docs.label, 'The count as a sentence, for a view.');
  // a named fixture says when to prefer it over the bare constructor
  assert.match(comp.inits[0].doc, /Starts at three/);
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
  const a2 = a.handleEvent('input', 'inc', []);
  assert.ok(a2 instanceof guest.Instance);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 11 });
  assert.deepEqual(a.getField('count'), { tag: 'number', val: 10 });
  assert.equal(a.handleEvent('input', 'unknown', []), undefined);
  assert.equal(a.handleEvent('receive', 'init', []), undefined);
});

test('the declared fields ARE the projection: no to-json, no eq', () => {
  // Both used to be guest methods. The host reads the fields the manifest
  // declares instead (Value::to_json / Obj::obj_eq over obj_schema), so a
  // guest states its shape once and cannot restate it wrongly.
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 5 }]]);
  const c = a.handleEvent('input', 'inc', []);
  assert.equal(a.toJson, undefined);
  assert.equal(a.eq, undefined);
  assert.deepEqual(c.getField('count'), { tag: 'number', val: 6 });
  const hist = c.getField('history');
  assert.deepEqual(arena.get(hist.val).map((v) => v.val), [5]);
});

test('history crosses as an arena list; label is a callable method', () => {
  const a = new guest.Instance('Counter', []);
  const a1 = a.handleEvent('input', 'inc', []);
  const a2 = a1.handleEvent('input', 'inc', []);
  const hist = a2.getField('history');
  assert.equal(hist.tag, 'list');
  assert.deepEqual(arena.get(hist.val).map((v) => v.val), [0, 1]);
  assert.deepEqual(a2.callMethod('label', []), { tag: 'text', val: 'count is 2' });
});

test('input "double" buffers a control request; the response applies it', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 21 }]]);
  controlBuf = [];
  assert.equal(a.handleEvent('input', 'double', []), undefined);
  assert.equal(controlBuf.length, 1);
  assert.equal(controlBuf[0].kind, 'request');
  assert.equal(controlBuf[0].name, 'double');
  assert.deepEqual(controlBuf[0].args[0], { tag: 'number', val: 21 });
  // the guest asked for the answer at a name of its own, carrying just the
  // value (host RequestOpts.on_ok_name)
  assert.equal(controlBuf[0].opts.onOk, 'doubled');
  assert.equal(controlBuf[0].opts.livePath, false);
  const a2 = a.handleEvent('response', 'doubled', [{ tag: 'number', val: 42 }]);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 42 });
});

test('the bundle serves its own requests', () => {
  // "triple" is declared by the Pair and answered here, in the guest — the
  // host registers it into the bundle's scope and calls back in
  const ok = guest.handleRequest('triple', [{ tag: 'number', val: 7 }]);
  assert.deepEqual(ok, { tag: 'ok', val: { tag: 'number', val: 21 } });
  const err = guest.handleRequest('nope', []);
  assert.equal(err.tag, 'err');
});

test('a guest emits a bubble, and a guest parent stops it', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 4 }]]);
  controlBuf = [];
  assert.equal(a.handleEvent('input', 'announce', []), undefined);
  assert.deepEqual(controlBuf, [
    { kind: 'emit', name: 'counted', args: [{ tag: 'number', val: 4 }] },
  ]);
  // the Pair hears that bubble one level up: it swaps its children and stops
  // the message from travelling further
  const p = new guest.Instance('Pair', []);
  drainChildren();
  const left = p.getField('left');
  const right = p.getField('right');
  controlBuf = [];
  const p2 = p.handleEvent('bubble', 'counted', [{ tag: 'number', val: 4 }]);
  assert.deepEqual(controlBuf, [{ kind: 'stopPropagation' }]);
  assert.deepEqual(p2.getField('left'), right);
  assert.deepEqual(p2.getField('right'), left);
});

test('a guest addresses its own subtree with send-at', () => {
  const p = new guest.Instance('Pair', []);
  drainChildren();
  controlBuf = [];
  assert.equal(p.handleEvent('input', 'zeroLeft', []), undefined);
  assert.equal(controlBuf.length, 1);
  const [msg] = controlBuf;
  assert.equal(msg.kind, 'sendAt');
  assert.equal(msg.name, 'sum');
  // one relative step: the child the `left` field holds
  assert.deepEqual(msg.path, [{ tag: 'field', val: 'left' }]);
});

test('a @when filter is a method that answers a boolean', () => {
  const a = new guest.Instance('Counter', []);
  // called with (key, item, iter-data) — the zero the counter started at is
  // filtered out of the history badges
  assert.deepEqual(
    a.callMethod('nonZero', [{ tag: 'text', val: 'h0' }, { tag: 'number', val: 0 }, { tag: 'nil' }]),
    { tag: 'boolean', val: false },
  );
  assert.deepEqual(
    a.callMethod('nonZero', [{ tag: 'text', val: 'h1' }, { tag: 'number', val: 3 }, { tag: 'nil' }]),
    { tag: 'boolean', val: true },
  );
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
  const summed = b.handleEvent('receive', 'sum', [{ tag: 'list', val: list }]);
  assert.deepEqual(summed.getField('count'), { tag: 'number', val: 42 });
  assert.equal(importCalls, 4); // 1 list-len + 3 list-get
});

test('a component that does not persist says so, and refuses bytes', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 5 }]]);
  // Empty is a DECISION: this counter's state is exactly its declared fields,
  // so the host projects and rebuilds it without any guest code, and writing
  // a `persist` here would be that list of fields written a second time.
  assert.deepEqual(a.persist(), new Uint8Array(0));
  // and with no format of its own it has nothing to read back
  assert.equal(guest.Instance.restore('Counter', new Uint8Array(0)), undefined);
  assert.equal(guest.Instance.restore('Counter', new TextEncoder().encode('{}')), undefined);
  // an unknown component is refused rather than guessed at
  assert.equal(guest.Instance.restore('Nope', new Uint8Array(0)), undefined);
});
