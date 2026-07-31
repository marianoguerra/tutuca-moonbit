// The polyglot proof: the SAME fake-host protocol that drives the MoonBit
// counter (harness.test.mjs) drives a guest written in Rust with zero
// tutuca code. Build it first:
//   node guests/rust-notepad/build.mjs
// then:
//   node --test dyncomp/test/rust-harness.test.mjs
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/rust-notepad/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('rust-notepad.component.js', jsDir)));

let controlBuf = [];
const control = {
  log: () => {},
  emit: (name, args) => controlBuf.push({ kind: 'emit', name, args }),
  send: (name, args) => controlBuf.push({ kind: 'send', name, args }),
  request: (name, args) => controlBuf.push({ kind: 'request', name, args }),
  makeInstance: () => 0n,
  dropInstance: () => {},
};
// A real arena this time: the notepad's state is a list of records, so a fake
// that answered nothing would make every assertion below vacuous.
const arena = new Map();
let nextHandle = 1n;
const put = (v) => { const h = nextHandle++; arena.set(h, v); return h; };
const values = {
  listLen: (h) => arena.get(h).length >>> 0,
  listGet: (h, i) => arena.get(h)[i],
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

/// A list-of-records field, read back out of the arena as plain JS.
const records = (v) =>
  arena.get(v.val).map((m) => Object.fromEntries([...arena.get(m.val)].map(([k, x]) => [k, x.val])));

let guest;
before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('rust-notepad.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    'tutuca:component/values@0.4.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.4.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
});

test('rust guest speaks the same contract', { skip: !built }, () => {
  const m = guest.getManifest();
  assert.equal(m.apiVersion, 4);
  assert.equal(m.moduleName, 'rustnotepadlib');
  assert.match(m.components[0].views[0].html, /@on\.click="addTab"/);

  const a = new guest.Instance('Notepad', []);
  // a fresh notepad opens with one note, so there is somewhere to type
  assert.deepEqual(records(a.getField('tabs')), [{ name: 'note 1', content: '', active: true }]);
  const a2 = a.handleEvent('input', 'edit', [{ tag: 'text', val: 'hello' }]);
  assert.deepEqual(records(a2.getField('tabs')), [{ name: 'note 1', content: 'hello', active: true }]);
  // self in, self out: the predecessor is untouched
  assert.deepEqual(records(a.getField('tabs')), [{ name: 'note 1', content: '', active: true }]);
  assert.deepEqual(a2.callMethod('content', []), { tag: 'text', val: 'hello' });

  // the same declared schema every guest ships: fields over a flat type table,
  // and the same metadata — written by hand in Rust, with no tutuca code
  assert.deepEqual(m.components[0].fields.map((f) => [f.name, f.ty]), [['tabs', 3], ['selected', 1]]);
  assert.equal(m.components[0].types[3].kind, 'ty-list');
  assert.equal(m.components[0].types[3].elem, 2);
  assert.equal(m.components[0].fields[1].constraint.min, 0);
  assert.ok(m.components[0].keywords.includes('rust'));
  assert.deepEqual(m.capabilities, []);
  // `setSelected` is the host's mutator, not a handler this guest answers
  assert.deepEqual(m.components[0].handlers, ['addTab', 'removeAt', 'renameSelected', 'edit']);
  assert.deepEqual(m.components[0].inits.map((i) => i.name), ['scratch']);
});

test('tabs are added, renamed, switched and removed', { skip: !built }, () => {
  let n = new guest.Instance('Notepad', []);
  n = n.handleEvent('input', 'renameSelected', [{ tag: 'text', val: 'shopping' }]);
  n = n.handleEvent('input', 'addTab', []);
  // adding opens the new note, so what you type next lands in it
  assert.deepEqual(n.getField('selected'), { tag: 'number', val: 1 });
  n = n.handleEvent('input', 'edit', [{ tag: 'text', val: 'second' }]);
  assert.deepEqual(records(n.getField('tabs')), [
    { name: 'shopping', content: '', active: false },
    // `active` rides with the item because `@each` takes a field, not a
    // method — and it is derived per read, so it cannot disagree with
    // `selected`
    { name: 'note 2', content: 'second', active: true },
  ]);

  // switching tabs is the host writing the declared field — no guest handler
  const back = n.withField('selected', { tag: 'number', val: 0 });
  assert.deepEqual(back.callMethod('tabName', []), { tag: 'text', val: 'shopping' });
  // and the field itself says which one is open, so a view needs no comparison
  assert.deepEqual(records(back.getField('tabs')).map((t) => t.active), [true, false]);

  // removing the open note lands on the one before it
  const one = n.handleEvent('input', 'removeAt', [{ tag: 'number', val: 1 }]);
  assert.deepEqual(records(one.getField('tabs')), [{ name: 'shopping', content: '', active: true }]);
  assert.deepEqual(one.getField('selected'), { tag: 'number', val: 0 });
  // an index that is not a note changes nothing
  assert.equal(one.handleEvent('input', 'removeAt', [{ tag: 'number', val: 9 }]), undefined);
});

test('a notepad persists and restores its own bytes', { skip: !built }, () => {
  let n = new guest.Instance('Notepad', []);
  n = n.handleEvent('input', 'edit', [{ tag: 'text', val: 'first note ✍' }]);
  n = n.handleEvent('input', 'addTab', []);
  n = n.handleEvent('input', 'renameSelected', [{ tag: 'text', val: 'plans' }]);

  const bytes = n.persist();
  assert.ok(bytes.length > 0);
  const back = guest.Instance.restore('Notepad', bytes);
  assert.deepEqual(records(back.getField('tabs')), [
    { name: 'note 1', content: 'first note ✍', active: false },
    { name: 'plans', content: '', active: true },
  ]);
  // WHICH tab was open is the half the declared fields would keep too — but
  // the note's text is not, and both survive because the guest wrote them
  assert.deepEqual(back.getField('selected'), { tag: 'number', val: 1 });

  // bytes from another format are refused rather than half-read: the host
  // then rebuilds from the declared fields instead
  assert.equal(guest.Instance.restore('Notepad', new TextEncoder().encode('nope')), undefined);
  assert.equal(guest.Instance.restore('Notepad', new Uint8Array(0)), undefined);
  // and bytes are per COMPONENT, not per bundle
  assert.equal(guest.Instance.restore('Somethingelse', bytes), undefined);
});
