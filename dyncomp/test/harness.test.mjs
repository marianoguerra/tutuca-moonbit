// Node harness for the tutuca:component contract, driven against the
// counter guest (guests/counter). Build it first:
//   node guests/build-guest.mjs counter
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
  send: (name, args) => controlBuf.push({ kind: 'send', name, args }),
  sendAt: (path, name, args) => controlBuf.push({ kind: 'sendAt', path, name, args }),
  intent: (name, args, opts) => controlBuf.push({ kind: 'intent', name, args, opts }),
  intentAt: (path, name, args, opts) => controlBuf.push({ kind: 'intentAt', path, name, args, opts }),
  forward: (args, opts) => controlBuf.push({ kind: 'forward', args, opts }),
  reply: (v) => controlBuf.push({ kind: 'reply', value: v }),
  fail: (e) => controlBuf.push({ kind: 'fail', value: e }),
  stopPropagation: () => controlBuf.push({ kind: 'stopPropagation' }),
  sendReply: (name, args) => controlBuf.push({ kind: 'sendReply', name, args }),
  lookup: () => ({ tag: 'nil' }),
  makeInstance: (component, args) => {
    const t = nextChild++;
    pendingChildren.push({ token: t, component, args });
    return BigInt(t);
  },
  dropInstance: (t) => children.delete(Number(t)),
};

let guest;
let manifest;
let rawHandleMessage;
before(async () => {
  const { instantiate } = await import(new URL('counter.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    // jco emits unversioned import keys today; provide both to be safe.
    'tutuca:component/values@0.11.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.11.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
  manifest = JSON.parse(
    await readFile(new URL('../../guests/counter/manifest.json', import.meta.url), 'utf8'),
  );
  for (const component of manifest.components) {
    for (const view of component.views) {
      view.html = await readFile(new URL(`../../guests/counter/${view.src}`, import.meta.url), 'utf8');
    }
  }
  // Most behavioral assertions care about the successor. Keep those terse,
  // while retaining the raw v0.6 method for the result-semantics assertion.
  rawHandleMessage = guest.Instance.prototype.handleMessage;
  guest.Instance.prototype.handleMessage = function (...args) {
    const result = rawHandleMessage.call(this, ...args);
    return result.tag === 'changed' ? result.val : undefined;
  };
  const rawHandleIntent = guest.Instance.prototype.handleIntent;
  guest.Instance.prototype.handleIntent = function (...args) {
    const result = rawHandleIntent.call(this, ...args);
    return result.tag === 'changed' ? result.val : undefined;
  };
});

test('manifest declares the component, its views and its state', () => {
  const m = manifest;
  assert.equal(m.apiVersion, 10);
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
  // "" and an absent key are the same thing — "not stated" — so the manifest
  // writes only the keys it means. Filling the record in is what states bounds
  // nobody meant, and a `0` written to fill it in is a real bound: see the
  // INERT_CONSTRAINT hint the host raises at load.
  assert.equal(comp.fields[0].constraint.format, undefined);
  assert.equal(comp.fields[0].constraint.pattern, undefined);
  assert.equal(comp.fields[1].constraint, undefined);
  assert.equal(comp.types[0].kind, 'ty-float');
  assert.equal(comp.types[1].kind, 'ty-list');
  assert.equal(comp.types[1].elem, 0);
  assert.equal(comp.handlers, undefined);
  // `doubled` and `triple` are ANSWERS, and an answer is an ordinary message:
  // it arrives in `receives` beside the ones a parent sends.
  assert.deepEqual(comp.receives, ['init', 'sum', 'doubled', 'tripled']);
  assert.equal(comp.bubbles, undefined);
  assert.equal(comp.responses, undefined);
  assert.deepEqual(comp.methods, ['label']);
  assert.deepEqual(comp.whens, ['nonZero']);
  // this component serves no intents; the Pair declares the bundle's one
  assert.deepEqual(comp.serves, []);
  assert.deepEqual(m.components[1].serves, ['triple']);
  // view handler names are NOT declared: the host reads them off the views
  assert.equal(comp.viewHandlers, undefined);
  assert.equal(comp.views[0].name, 'main');
  assert.match(comp.views[0].html, /@on\.click="inc"/);
  assert.match(comp.views[0].html, /@text="\.count"/);
  // the guests carry no CSS of their own any more — the views style
  // themselves with margaui utility classes (the universal-wasm commit), which
  // is also what the host's strictest style tier requires
  assert.equal(comp.style, '');
});

test('the manifest carries what a catalog and a model read', () => {
  const m = manifest;
  assert.match(m.doc, /reference bundle/);
  assert.equal(m.version, '0.4.0');
  // the manifest declares no capabilities — the vocabulary is gone; anything
  // a guest cannot compute for itself it asks the host for over an intent
  assert.ok(!('capabilities' in m));
  const [comp] = m.components;
  assert.match(comp.doc, /buttons that raise and lower it/);
  assert.ok(comp.keywords.includes('tally'));
  assert.equal(comp.category, 'input');
  // one flat table the host merges by name over the bucket lists
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

test('handle-message is functional: new instance out, old unchanged', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 10 }]]);
  const a2 = a.handleMessage('inc', []);
  assert.ok(a2 instanceof guest.Instance);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 11 });
  assert.deepEqual(a.getField('count'), { tag: 'number', val: 10 });
  assert.equal(a.handleMessage('unknown', []), undefined);
  assert.equal(a.handleMessage('init', []), undefined);
});

test('handle-message distinguishes unknown names from handled no-ops', () => {
  const a = new guest.Instance('Counter', []);
  assert.deepEqual(rawHandleMessage.call(a, 'unknown', []), { tag: 'unhandled' });
  assert.deepEqual(rawHandleMessage.call(a, 'init', []), { tag: 'unchanged' });
  const result = rawHandleMessage.call(a, 'inc', []);
  assert.equal(result.tag, 'changed');
  assert.ok(result.val instanceof guest.Instance);
});

test('the declared fields ARE the projection: no to-json, no eq', () => {
  // Both used to be guest methods. The host reads the fields the manifest
  // declares instead (Value::to_json / Obj::obj_eq over obj_schema), so a
  // guest states its shape once and cannot restate it wrongly.
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 5 }]]);
  const c = a.handleMessage('inc', []);
  assert.equal(a.toJson, undefined);
  assert.equal(a.eq, undefined);
  assert.deepEqual(c.getField('count'), { tag: 'number', val: 6 });
  const hist = c.getField('history');
  assert.deepEqual(arena.get(hist.val).map((v) => v.val), [5]);
});

test('history crosses as an arena list; label is a callable method', () => {
  const a = new guest.Instance('Counter', []);
  const a1 = a.handleMessage('inc', []);
  const a2 = a1.handleMessage('inc', []);
  const hist = a2.getField('history');
  assert.equal(hist.tag, 'list');
  assert.deepEqual(arena.get(hist.val).map((v) => v.val), [0, 1]);
  assert.deepEqual(a2.compute('label', []), { tag: 'text', val: 'count is 2' });
});

test('"double" raises a lex intent, and its answer applies', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 21 }]]);
  controlBuf = [];
  assert.equal(a.handleMessage('double', []), undefined);
  assert.equal(controlBuf.length, 1);
  assert.equal(controlBuf[0].kind, 'intent');
  assert.equal(controlBuf[0].name, 'double');
  assert.deepEqual(controlBuf[0].args[0], { tag: 'number', val: 21 });
  // the guest asked for the answer at a name of its own, carrying just the
  // value (the intent opts' on_ok name)
  assert.equal(controlBuf[0].opts.onOk, 'doubled');
  assert.equal(controlBuf[0].opts.livePath, false);
  const a2 = a.handleMessage('doubled', [{ tag: 'number', val: 42 }]);
  assert.deepEqual(a2.getField('count'), { tag: 'number', val: 42 });
});

test('the bundle serves its own intents', () => {
  // "triple" is declared by the Pair and answered here, in the guest — the
  // host registers it into the bundle's scope and calls back in
  const ok = guest.serveIntent('triple', [{ tag: 'number', val: 7 }]);
  assert.deepEqual(ok, { tag: 'ok', val: { tag: 'number', val: 21 } });
  const err = guest.serveIntent('nope', []);
  assert.equal(err.tag, 'err');
});

test('a guest raises an intent, and a guest parent ends the walk', () => {
  const a = new guest.Instance('Counter', [['count', { tag: 'number', val: 4 }]]);
  controlBuf = [];
  assert.equal(a.handleMessage('announce', []), undefined);
  assert.equal(controlBuf.length, 1);
  assert.equal(controlBuf[0].kind, 'intent');
  assert.equal(controlBuf[0].name, 'counted');
  assert.deepEqual(controlBuf[0].args, [{ tag: 'number', val: 4 }]);
  // it walks the `dyn` leg: the sender's parent first, then up
  assert.deepEqual(controlBuf[0].opts.route, ['dyn']);
  // the Pair answers it one level up: it swaps its children and ends the walk
  // so the intent travels no further
  const p = new guest.Instance('Pair', []);
  drainChildren();
  const left = p.getField('left');
  const right = p.getField('right');
  controlBuf = [];
  const p2 = p.handleIntent('counted', [{ tag: 'number', val: 4 }]);
  assert.deepEqual(controlBuf, [{ kind: 'stopPropagation' }]);
  assert.deepEqual(p2.getField('left'), right);
  assert.deepEqual(p2.getField('right'), left);
});

test('a guest addresses its own subtree with send-at', () => {
  const p = new guest.Instance('Pair', []);
  drainChildren();
  controlBuf = [];
  assert.equal(p.handleMessage('zeroLeft', []), undefined);
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
    a.compute('nonZero', [{ tag: 'text', val: 'h0' }, { tag: 'number', val: 0 }, { tag: 'nil' }]),
    { tag: 'boolean', val: false },
  );
  assert.deepEqual(
    a.compute('nonZero', [{ tag: 'text', val: 'h1' }, { tag: 'number', val: 3 }, { tag: 'nil' }]),
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
  const summed = b.handleMessage('sum', [{ tag: 'list', val: list }]);
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
