// TodoMVC over the contract, driven headlessly by the same fake host the
// other two harnesses use. Build it first:
//   node guests/build-guest.mjs todomvc
// then:
//   node --test dyncomp/test/todomvc-harness.test.mjs
//
// What is worth checking here is not "does a todo list work" but the split the
// guest makes: `items` and `filter` are DECLARED (so the host owns setFilter,
// the projection and equality), while the draft, the row being edited and its
// text are the guest's own — invisible to the host, and kept anyway because
// `persist` writes them.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/todomvc/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('todomvc.component.js', jsDir)));

const control = {
  log: () => {},
  emit: () => {},
  send: () => {},
  sendAt: () => {},
  bubbleAt: () => {},
  stopPropagation: () => {},
  request: () => {},
  after: () => {},
  makeInstance: () => 0n,
  dropInstance: () => {},
};

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

const text = (val) => ({ tag: 'text', val });
const num = (val) => ({ tag: 'number', val });
const bool = (val) => ({ tag: 'boolean', val });
/// The `items` field, as plain JS.
const rows = (v) =>
  arena.get(v.val).map((m) => Object.fromEntries([...arena.get(m.val)].map(([k, x]) => [k, x.val])));
/// Type a task and add it, the way the view does.
const add = (inst, what) =>
  inst.handleEvent('input', 'typeDraft', [text(what)]).handleEvent('input', 'add', []);
/// What the `@when` filter answers for row `i` — the host calls this per item
/// while iterating, which is why a filtered list keeps the real indices.
const shown = (inst) =>
  rows(inst.getField('items')).filter((_, i) => {
    const item = arena.get(inst.getField('items').val)[i];
    return inst.callMethod('matchesFilter', [num(i), item, { tag: 'nil' }]).val;
  });

let guest;
before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('todomvc.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    'tutuca:component/values@0.5.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.5.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
});

test('the manifest declares two fields and eleven handlers', { skip: !built }, () => {
  const m = guest.getManifest();
  assert.equal(m.apiVersion, 5);
  assert.equal(m.moduleName, 'todomvclib');
  const [c] = m.components;
  assert.equal(c.name, 'TodoMvc');
  assert.deepEqual(c.fields.map((f) => f.name), ['items', 'filter']);
  // the filter's three words are a CONSTRAINT, so a generated form offers a
  // choice rather than a text box
  assert.equal(c.fields[1].constraint.enumJson, '["all", "active", "completed"]');
  assert.equal(c.fields[1].constraint.defaultJson, '"all"');
  // `setFilter` is the host's mutator; the guest never answers that name
  assert.ok(!c.handlers.includes('setFilter'));
  assert.deepEqual(c.whens, ['matchesFilter']);
  assert.deepEqual(c.inits.map((i) => i.name), ['example']);
});

test('add, toggle, toggle-all and clear-completed', { skip: !built }, () => {
  let t = new guest.Instance('TodoMvc', []);
  t = add(t, 'write the guest');
  t = add(t, 'build the bundle');
  // a blank draft adds nothing
  assert.equal(t.handleEvent('input', 'add', []), undefined);
  assert.deepEqual(rows(t.getField('items')).map((r) => r.text), [
    'write the guest',
    'build the bundle',
  ]);

  t = t.handleEvent('input', 'toggleAt', [num(0)]);
  assert.deepEqual(rows(t.getField('items')).map((r) => r.done), [true, false]);
  assert.deepEqual(t.callMethod('countLeft', []), text('1 item left'));

  // toggle-all turns everything on, then off again once it all is
  t = t.handleEvent('input', 'toggleAll', []);
  assert.deepEqual(rows(t.getField('items')).map((r) => r.done), [true, true]);
  assert.deepEqual(t.callMethod('countLeft', []), text('0 items left'));
  const off = t.handleEvent('input', 'toggleAll', []);
  assert.deepEqual(rows(off.getField('items')).map((r) => r.done), [false, false]);

  const cleared = t.handleEvent('input', 'clearCompleted', []);
  assert.deepEqual(rows(cleared.getField('items')), []);
});

test('filtering happens in the @when, so the real indices survive', { skip: !built }, () => {
  let t = new guest.Instance('TodoMvc', []);
  t = add(t, 'one');
  t = add(t, 'two');
  t = add(t, 'three');
  t = t.handleEvent('input', 'toggleAt', [num(1)]);

  // the filter is a DECLARED field, so switching it is the host writing
  // through with-field — no guest handler is involved
  const active = t.withField('filter', text('active'));
  assert.deepEqual(shown(active).map((r) => r.text), ['one', 'three']);
  const done = t.withField('filter', text('completed'));
  assert.deepEqual(shown(done).map((r) => r.text), ['two']);
  assert.deepEqual(shown(t).map((r) => r.text), ['one', 'two', 'three']);

  // a filter nobody defined is refused rather than showing nothing
  assert.equal(t.withField('filter', text('sideways')), undefined);

  // and while filtered, a per-row handler still names the row by its index in
  // the WHOLE list, which is what makes the filter free
  const removed = done.handleEvent('input', 'removeAt', [num(1)]);
  assert.deepEqual(rows(removed.getField('items')).map((r) => r.text), ['one', 'three']);
});

test('editing in place: open, type, commit — or empty it and it is gone', { skip: !built }, () => {
  let t = new guest.Instance('TodoMvc', []);
  t = add(t, 'first');
  t = add(t, 'second');

  t = t.handleEvent('input', 'startEdit', [num(1)]);
  // the row says it is being edited, which is how the view swaps the label
  // for a box without the host knowing anything about editing
  assert.deepEqual(rows(t.getField('items')).map((r) => r.editing), [false, true]);
  assert.deepEqual(t.callMethod('editText', []), text('second'));

  t = t.handleEvent('input', 'typeEdit', [text('second, edited')]);
  const kept = t.handleEvent('input', 'commitEdit', [bool(true)]);
  assert.deepEqual(rows(kept.getField('items')).map((r) => r.text), ['first', 'second, edited']);
  assert.deepEqual(rows(kept.getField('items')).map((r) => r.editing), [false, false]);

  // abandoning keeps what was there
  const abandoned = t.handleEvent('input', 'cancelEdit', []);
  assert.deepEqual(rows(abandoned.getField('items')).map((r) => r.text), ['first', 'second']);

  // committing an empty row deletes it, as TodoMVC specifies
  const emptied = t
    .handleEvent('input', 'typeEdit', [text('   ')])
    .handleEvent('input', 'commitEdit', [bool(true)]);
  assert.deepEqual(rows(emptied.getField('items')).map((r) => r.text), ['first']);
});

test('persist keeps what the declared fields do not', { skip: !built }, () => {
  let t = new guest.Instance('TodoMvc', []);
  t = add(t, 'shopping');
  t = t.withField('filter', text('active'));
  t = t.handleEvent('input', 'typeDraft', [text('half-typed thought')]);
  t = t.handleEvent('input', 'startEdit', [num(0)]);
  t = t.handleEvent('input', 'typeEdit', [text('shopping list')]);

  const back = guest.Instance.restore('TodoMvc', t.persist());
  // the declared half
  assert.deepEqual(rows(back.getField('items')).map((r) => r.text), ['shopping']);
  assert.deepEqual(back.getField('filter'), text('active'));
  // and the half the host could never have projected
  assert.deepEqual(back.callMethod('draft', []), text('half-typed thought'));
  assert.deepEqual(back.callMethod('editText', []), text('shopping list'));
  assert.deepEqual(rows(back.getField('items')).map((r) => r.editing), [true]);

  // bytes from elsewhere are refused, and the host falls back to the fields
  assert.equal(guest.Instance.restore('TodoMvc', new TextEncoder().encode('{"v":9}')), undefined);
  assert.equal(guest.Instance.restore('TodoMvc', new Uint8Array(0)), undefined);
});
