// The polyglot proof: the SAME fake-host protocol that drives the MoonBit
// counter (harness.test.mjs) drives a guest written in Rust with zero
// tutuca code. Build it first:
//   node guests/rust-tempconv/build.mjs
// then:
//   node --test dyncomp/test/rust-harness.test.mjs
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/rust-tempconv/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('rust-tempconv.component.js', jsDir)));

let controlBuf = [];
const control = {
  log: () => {},
  emit: (name, args) => controlBuf.push({ kind: 'emit', name, args }),
  send: (name, args) => controlBuf.push({ kind: 'send', name, args }),
  request: (name, args) => controlBuf.push({ kind: 'request', name, args }),
  makeInstance: () => 0n,
  dropInstance: () => {},
};
// A real arena, because a fake that answered nothing would make every
// assertion below vacuous — the guest builds values through these imports.
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

let guest;
let manifest;
before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('rust-tempconv.component.js', jsDir));
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
    await readFile(new URL('../../guests/rust-tempconv/manifest.json', import.meta.url), 'utf8'),
  );
  const raw = guest.Instance.prototype.handleEvent;
  guest.Instance.prototype.handleEvent = function (...args) {
    const result = raw.call(this, ...args);
    return result.tag === 'changed' ? result.val : undefined;
  };
});

/// A method's answer, as plain text.
const said = (inst, name) => inst.callMethod(name, []).val;

test('rust guest speaks the same contract', { skip: !built }, () => {
  const m = manifest;
  assert.equal(m.apiVersion, 6);
  assert.equal(m.moduleName, 'rusttemplib');
  assert.equal(m.components[0].views[0].src, 'views/TempConv.main.html');

  // 20°C rather than 0: three zeros would not demonstrate a conversion
  const a = new guest.Instance('TempConv', []);
  assert.deepEqual(a.getField('celsius'), { tag: 'number', val: 20 });
  assert.equal(said(a, 'fText'), '68');
  assert.equal(said(a, 'kText'), '293.15');
  assert.equal(said(a, 'note'), 'room temperature');

  const b = a.handleEvent('input', 'editF', [{ tag: 'text', val: '212' }]);
  assert.deepEqual(b.getField('celsius'), { tag: 'number', val: 100 });
  assert.equal(said(b, 'note'), 'water boils');
  // self in, self out: the predecessor is untouched
  assert.deepEqual(a.getField('celsius'), { tag: 'number', val: 20 });

  // the same declared schema every guest ships: fields over a flat type table,
  // and the same metadata — written by hand in Rust, with no tutuca code
  assert.deepEqual(m.components[0].fields.map((f) => [f.name, f.ty]), [['celsius', 0]]);
  assert.equal(m.components[0].types[0].kind, 'ty-float');
  // absolute zero is a floor the physics gives us
  assert.equal(m.components[0].fields[0].constraint.min, -273.15);
  assert.ok(m.components[0].keywords.includes('rust'));
  assert.deepEqual(m.capabilities, []);
  // `setCelsius` is the host's mutator, not a handler this guest answers
  assert.equal(m.components[0].handlers, undefined);
  assert.deepEqual(m.components[0].inits.map((i) => i.name), ['body-heat']);
});

test('the box being typed in keeps its characters', { skip: !built }, () => {
  let t = new guest.Instance('TempConv', []);
  t = t.handleEvent('input', 'preset', [{ tag: 'number', val: 37 }]);
  assert.equal(said(t, 'cText'), '37');
  assert.equal(said(t, 'fText'), '98.6');

  // A lone minus is a real thing to have typed on the way to a number. It is
  // not a number, so the temperature does not move — but the box has to show
  // it, or the character disappears as you type it.
  const drafting = t.handleEvent('input', 'editC', [{ tag: 'text', val: '-' }]);
  assert.equal(said(drafting, 'cText'), '-');
  assert.equal(said(drafting, 'fText'), '98.6');
  assert.deepEqual(drafting.getField('celsius'), { tag: 'number', val: 37 });

  // ...and a box that is NOT being typed in shows the number, formatted.
  const typed = t.handleEvent('input', 'editC', [{ tag: 'text', val: '-40' }]);
  assert.equal(said(typed, 'cText'), '-40');
  assert.equal(said(typed, 'fText'), '-40');

  // A preset settles everything: no draft, so every box shows its number.
  const settled = typed.handleEvent('input', 'preset', [{ tag: 'number', val: 0 }]);
  assert.equal(said(settled, 'cText'), '0');
  assert.equal(said(settled, 'note'), 'water freezes');

  // Below absolute zero is not a temperature, so it is clamped rather than
  // refused: the number arrives a keystroke at a time.
  const cold = settled.handleEvent('input', 'editK', [{ tag: 'text', val: '-5' }]);
  assert.deepEqual(cold.getField('celsius'), { tag: 'number', val: -273.15 });

  // Writing the declared field is the host's mutator, and it settles the draft
  // for the same reason a preset does.
  const written = drafting.withField('celsius', { tag: 'number', val: 100 });
  assert.equal(said(written, 'cText'), '100');
});

test('a converter persists and restores its own bytes', { skip: !built }, () => {
  let t = new guest.Instance('TempConv', []);
  t = t.handleEvent('input', 'editF', [{ tag: 'text', val: '98.6' }]);
  // Mid-edit, in a box, with a lone minus: a real thing to have typed and not
  // a number, so the temperature is still body heat underneath it.
  t = t.handleEvent('input', 'editC', [{ tag: 'text', val: '-' }]);

  const bytes = t.persist();
  assert.ok(bytes.length > 0);
  const back = guest.Instance.restore('TempConv', bytes);
  // The temperature is the half the declared field would keep too. WHICH box
  // was being typed in, and what was in it, is the half it would not — and
  // both survive because the guest wrote them.
  assert.deepEqual(back.getField('celsius'), { tag: 'number', val: 37 });
  assert.equal(said(back, 'cText'), '-');
  assert.equal(said(back, 'fText'), '98.6');

  // A draft that IS a number still comes back as typed rather than as
  // formatted: `-4.` parses, so the temperature moves, but the box keeps the
  // trailing point somebody is about to type digits after.
  const mid = t.handleEvent('input', 'editC', [{ tag: 'text', val: '-4.' }]);
  const midBack = guest.Instance.restore('TempConv', mid.persist());
  assert.deepEqual(midBack.getField('celsius'), { tag: 'number', val: -4 });
  assert.equal(said(midBack, 'cText'), '-4.');

  // bytes from another format are refused rather than half-read: the host
  // then rebuilds from the declared fields instead
  assert.equal(guest.Instance.restore('TempConv', new TextEncoder().encode('nope')), undefined);
  assert.equal(guest.Instance.restore('TempConv', new Uint8Array(0)), undefined);
  // and bytes are per COMPONENT, not per bundle
  assert.equal(guest.Instance.restore('Somethingelse', bytes), undefined);
});
