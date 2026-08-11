// The table guest over the contract, driven headlessly by the same fake host
// the other harnesses use. Build it first:
//   node guests/build-guest.mjs table
// then:
//   node --test dyncomp/test/table-harness.test.mjs
//
// This is the ONLY runtime test of guests/tables.mbt — the codec that converts
// between the arena `values.value` a table arrives as and the `tables.*` types
// the contract declares. Its arena calls cannot run outside a real guest, so a
// unit test is not available; this is the substitute, and it is why the guest
// exists at all.
//
// Three things are worth checking here, and they are the three the design would
// be wrong about if it were wrong:
//
//   1. The null asymmetry round-trips. A missing value is inline `null` on the
//      wire and a sparse `nulls` index list in the WIT. Load a table with a gap,
//      read it back, and the gap has to be in the same place.
//   2. `apply_command` actually applies. The `command` variant is vocabulary;
//      sorting through it is what proves the vocabulary is spoken.
//   3. Sorting moves whole ROWS. A columnar table sorted one column at a time
//      is the classic way to shred a dataset, so the check is that the other
//      columns followed — including their nulls.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/table/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('table.component.js', jsDir)));

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
const nil = { tag: 'nil' };

/// Plain JS -> the tagged arena value the host would hand over. `null` becomes
/// `nil`, which is the whole point: that is how a missing cell travels.
const toGuest = (j) => {
  if (j === null || j === undefined) return nil;
  if (typeof j === 'boolean') return { tag: 'boolean', val: j };
  if (typeof j === 'number') return num(j);
  if (typeof j === 'string') return text(j);
  if (Array.isArray(j)) return { tag: 'list', val: put(j.map(toGuest)) };
  return { tag: 'map', val: put(new Map(Object.entries(j).map(([k, v]) => [k, toGuest(v)]))) };
};

/// ...and back, so a field read can be compared against plain JS.
const fromGuest = (v) => {
  if (!v || v.tag === 'nil') return null;
  if (v.tag === 'list') return arena.get(v.val).map(fromGuest);
  if (v.tag === 'map') return Object.fromEntries([...arena.get(v.val)].map(([k, x]) => [k, fromGuest(x)]));
  return v.val;
};

/// Four cities across all four column types, with one population missing.
/// The same fixture the component's `cities` init offers.
const CITIES = {
  columns: [
    { id: 'city', label: 'City', type: 'str', values: ['Berlin', 'Athens', 'Lima', 'Oslo'] },
    { id: 'pop', label: 'Population', type: 'i32', values: [3664000, 664000, null, 709000] },
    { id: 'lat', label: 'Latitude', type: 'f64', values: [52.52, 37.98, -12.05, 59.91] },
    { id: 'capital', label: 'Capital', type: 'bool', values: [true, true, true, true] },
  ],
};

let guest;
let manifest;
const make = (args) => new guest.Instance('Table', args);

before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('table.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    'tutuca:component/values@0.6.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.6.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
  manifest = JSON.parse(
    await readFile(new URL('../../guests/table/manifest.json', import.meta.url), 'utf8'),
  );
  const raw = guest.Instance.prototype.handleEvent;
  guest.Instance.prototype.handleEvent = function (...args) {
    const result = raw.call(this, ...args);
    return result.tag === 'changed' ? result.val : undefined;
  };
});

test('the manifest declares one ty-table field', { skip: !built }, () => {
  const m = manifest;
  assert.equal(m.apiVersion, 6);
  assert.equal(m.moduleName, 'tablelib');
  const [c] = m.components;
  assert.equal(c.name, 'Table');
  assert.deepEqual(c.fields.map((f) => f.name), ['data', 'pageSize']);
  // the kind that makes the host project a real schema instead of a stub
  assert.equal(c.types[c.fields[0].ty].kind, 'ty-table');
  assert.equal(c.fields[0].required, true);
  // the init fixture is the documented JSON shape, so it has to parse
  const fixture = JSON.parse(c.inits[0].argsJson);
  assert.equal(fixture.data.columns.length, 4);
});

test('a table survives the round trip, gap and all', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)]]);
  const back = fromGuest(inst.getField('data'));
  // rowCount is DERIVED, never read from the wire
  assert.equal(back.rowCount, 4);
  assert.deepEqual(back.columns.map((c) => c.id), ['city', 'pop', 'lat', 'capital']);
  assert.deepEqual(back.columns.map((c) => c.type), ['str', 'i32', 'f64', 'bool']);
  // the inline null went in as `nil`, became a sparse `nulls` index inside the
  // guest, and came back out inline in the same place
  assert.deepEqual(back.columns[1].values, [3664000, 664000, null, 709000]);
  assert.deepEqual(back.columns[0].values, ['Berlin', 'Athens', 'Lima', 'Oslo']);
  assert.deepEqual(back.columns[3].values, [true, true, true, true]);
});

test('paging shows a window, and clamps at both ends', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)], ['pageSize', num(3)]]);
  assert.equal(fromGuest(inst.getField('rowCount')), 4);
  assert.equal(fromGuest(inst.getField('pageCount')), 2);
  assert.deepEqual(fromGuest(inst.getField('rows')).map((r) => r[0]), ['Berlin', 'Athens', 'Lima']);

  const p2 = inst.handleEvent('input', 'nextPage', []);
  assert.equal(fromGuest(p2.getField('page')), 2);
  assert.deepEqual(fromGuest(p2.getField('rows')).map((r) => r[0]), ['Oslo']);

  // past the end is the last page, not an empty one
  const past = p2.handleEvent('input', 'nextPage', []);
  assert.equal(fromGuest(past.getField('page')), 2);
  const first = past.handleEvent('input', 'firstPage', []);
  assert.equal(fromGuest(first.getField('page')), 1);
  // and a missing cell renders as a gap, not as "null" or a zero
  const shown = fromGuest(first.getField('rows'));
  assert.equal(shown[2][1], '');
});

test('sorting moves whole rows, and missing values sort last', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)], ['pageSize', num(10)]]);
  const asc = inst.handleEvent('input', 'sortBy', [text('pop')]);
  const t = fromGuest(asc.getField('data'));
  // ascending by population, with the missing one last in BOTH directions
  assert.deepEqual(t.columns[1].values, [664000, 709000, 3664000, null]);
  // ...and every other column followed. This is the check that matters: a
  // columnar sort that forgets a column silently shreds the dataset.
  assert.deepEqual(t.columns[0].values, ['Athens', 'Oslo', 'Berlin', 'Lima']);
  assert.deepEqual(t.columns[2].values, [37.98, 59.91, 52.52, -12.05]);
  assert.equal(fromGuest(asc.getField('sort')), 'pop');
  assert.equal(fromGuest(asc.getField('descending')), false);

  // clicking the sorted column reverses it, and the gap STILL sorts last
  const desc = asc.handleEvent('input', 'sortBy', [text('pop')]);
  const d = fromGuest(desc.getField('data'));
  assert.deepEqual(d.columns[1].values, [3664000, 709000, 664000, null]);
  assert.deepEqual(d.columns[0].values, ['Berlin', 'Oslo', 'Athens', 'Lima']);
  assert.equal(fromGuest(desc.getField('descending')), true);

  // a column that is not there is a no-op, not a crash
  assert.equal(desc.handleEvent('input', 'sortBy', [text('nope')]), undefined);
});

test('sorting a str column orders text, and a bool column orders false first', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)]]);
  const byCity = fromGuest(inst.handleEvent('input', 'sortBy', [text('city')]).getField('data'));
  assert.deepEqual(byCity.columns[0].values, ['Athens', 'Berlin', 'Lima', 'Oslo']);
  // the null in `pop` travelled with Lima, which is now third
  assert.deepEqual(byCity.columns[1].values, [664000, 3664000, null, 709000]);

  const mixed = {
    columns: [
      { id: 'on', label: 'On', type: 'bool', values: [true, false, true] },
      { id: 'n', label: 'N', type: 'i32', values: [1, 2, 3] },
    ],
  };
  const b = fromGuest(
    make([['data', toGuest(mixed)]]).handleEvent('input', 'sortBy', [text('on')]).getField('data'),
  );
  assert.deepEqual(b.columns[0].values, [false, true, true]);
  assert.deepEqual(b.columns[1].values, [2, 1, 3]);
});

test('load replaces the data and clear keeps the columns', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)]]);
  const other = {
    columns: [{ id: 'a', label: 'A', type: 'str', values: ['x', 'y'] }],
  };
  const loaded = inst.handleEvent('receive', 'load', [toGuest(other)]);
  assert.equal(fromGuest(loaded.getField('rowCount')), 2);
  assert.equal(fromGuest(loaded.getField('colCount')), 1);
  // loading resets the sort, because the column it named may be gone
  assert.equal(fromGuest(loaded.getField('sort')), '');

  const cleared = loaded.handleEvent('receive', 'clear', []);
  assert.equal(fromGuest(cleared.getField('rowCount')), 0);
  assert.equal(fromGuest(cleared.getField('colCount')), 1, 'clear drops rows, not columns');
  assert.equal(fromGuest(cleared.getField('empty')), true);
  assert.deepEqual(fromGuest(cleared.getField('data')).columns[0].values, []);
});

test('an empty table is a table', { skip: !built }, () => {
  const inst = make([['data', toGuest({ columns: [] })]]);
  assert.equal(fromGuest(inst.getField('rowCount')), 0);
  assert.equal(fromGuest(inst.getField('empty')), true);
  // one page, not zero — "page 1 of 0" is not a thing a reader should see
  assert.equal(fromGuest(inst.getField('pageCount')), 1);
  assert.equal(fromGuest(inst.getField('summary')), '0 rows × 0 columns');

  // columns but no rows is a different, also-valid state
  const headers = make([
    ['data', toGuest({ columns: [{ id: 'a', label: 'A', type: 'i32', values: [] }] })],
  ]);
  assert.equal(fromGuest(headers.getField('colCount')), 1);
  assert.equal(fromGuest(headers.getField('rowCount')), 0);
});

test('withField is the host mutator writing a whole new table through', { skip: !built }, () => {
  const inst = make([['data', toGuest(CITIES)]]);
  const next = inst.withField('data', toGuest({
    columns: [{ id: 'z', label: 'Z', type: 'i32', values: [9, 8] }],
  }));
  assert.equal(fromGuest(next.getField('rowCount')), 2);
  assert.deepEqual(fromGuest(next.getField('data')).columns[0].values, [9, 8]);
});
