import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createTdomImports, registerDroppedFiles, takeDroppedFile } from './loader.mjs';

// Execute the actual inline JS backend helpers alongside the wasm imports.
const source = readFileSync(new URL('../browser/glue.mbt', import.meta.url), 'utf8');
function ffi(name) {
  const block = source.slice(source.indexOf(`extern "js" fn ${name}`)).split('///|')[0];
  return Function(`return (${block.split('\n').filter(l => l.trimStart().startsWith('#|')).map(l => l.slice(l.indexOf('#|') + 2)).join('\n')})`)();
}
const wasm = createTdomImports(() => null);
for (const [name, has, read, leaf] of [
  ['wasm', wasm.has_prop, wasm.read_prop, wasm.leaf_json],
  ['js', ffi('has_prop_ffi'), ffi('get_prop_ffi'), ffi('leaf_json_ffi')],
]) {
  test(`${name}: unresolved event paths cannot throw`, () => {
    for (const v of [null, undefined, 42, 'text', true]) assert.equal(has(v, 'field'), false);
    const hostile = { get field() { throw Error('getter'); } };
    assert.equal(read(hostile, 'field'), null);
    assert.equal(leaf(hostile, 'field'), '');
    assert.equal(leaf({ field: { value: 3 } }, 'field'), '{"value":3}');
    assert.equal(leaf({ field: new Date() }, 'field'), '');
    assert.equal(read({ detail: { value: 3 } }, 'detail').value, 3);
  });
}
test('wasm: every drop expires previous file identifiers', () => {
  const drop = name => ({ dataTransfer: { files: [{ name, size: 1, type: '', lastModified: 0 }] } });
  const [first] = JSON.parse(registerDroppedFiles(drop('a')));
  const [second] = JSON.parse(registerDroppedFiles(drop('b')));
  assert.notEqual(first.id, second.id);
  assert.equal(takeDroppedFile(first.id), undefined);
  assert.equal(takeDroppedFile(second.id).name, 'b');
  registerDroppedFiles({ dataTransfer: { files: [] } });
  assert.equal(takeDroppedFile(second.id), undefined);
});
test('js: every drop expires previous file identifiers', () => {
  const value = ffi('event_value_ffi');
  const drop = name => ({ type: 'drop', dataTransfer: { files: [{ name }] } });
  const [first] = value(drop('a'));
  const [second] = value(drop('b'));
  assert.notEqual(first.id, second.id);
  assert.equal(globalThis.__tutucaDroppedFile(first.id), undefined);
  value({ type: 'drop', dataTransfer: { files: [] } });
  assert.equal(globalThis.__tutucaDroppedFile(second.id), undefined);
});
