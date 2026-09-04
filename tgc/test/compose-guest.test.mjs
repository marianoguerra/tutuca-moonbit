// Two modules, one hole — through the bridge a PAGE uses.
//
// `compose.test.mjs` proves the format composes, and it proves it at the
// runtime: `rt.call_op` dispatches through the instance's own vtable, so a
// module holding another module's instance is one `call_ref` and always was.
// It never touches `__cardguest`.
//
// This does. `tutucard/web/card.js` is what a page loads a card through, and
// it is where a value crossing to the host is re-spelled as JSON — which is
// the one place an instance stops being a reference and becomes a name. A name
// has to be unique for the thing it names, and until it was, the two halves of
// composition were each correct and the pair was not:
//
//   inbound   a handle is minted per `loadGuest`, both tables starting at 1,
//             so B's handle 1 read in A answers A's first instance
//   outbound  the marker said which COMPONENT but not which MODULE, so the
//             host wrapped a foreign instance with the decoding module's
//             schema and drew one component's view over another's fields
//
// Neither failed loudly. That is the whole reason this file exists.
//
//   node --test tgc/test/compose-guest.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadGuest } from "../../tutucard/web/card.js";

const out = join(process.cwd(), "_build/tgc");
mkdirSync(out, { recursive: true });

const run = (args) =>
  execFileSync("moon", ["run", "--target", "native", ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
  });

run(["cmd/tgc", "--", "runtime", join(out, "compose-guest-rt.wasm")]);
const runtime = (
  await WebAssembly.instantiate(
    readFileSync(join(out, "compose-guest-rt.wasm")),
    {},
  )
).instance.exports;

// The holder. `child` is a bare `Instance`, so what goes in it is anybody's —
// which is the entire point: a card cannot BUILD another module's component and
// does not have to, because a host can PUT one here.
const KIT = `<script type="tutuca/spec">
  state Hole {
    child: Instance
    kept: String
  }
</script>
<script type="tutuca/script" for="Hole">
  compute innerBody { .child.body }
  compute innerSecret { .child.secret }
  receive rename(to) {
    .child.body = to
    .kept = 'wrote'
  }
  receive leak(to) {
    .child.secret = to
    .kept = 'leaked'
  }
</script>
<template id="Hole:main" data-root><i @text="$innerBody"></i></template>
`;

// The other module, which the holder has never heard of. `body` is public, and
// the declaration is the whole permission: a holder reaching `.child.body`
// reaches this and nothing else.
const NOTES = `<script type="tutuca/spec">
  state Note {
    body: String
    secret: String
    property { body: String { get .body set .body } }
  }
</script>
<template id="Note:main" data-root><b @text=".body"></b></template>
`;

async function load(source, stem) {
  const cardPath = join(out, `${stem}.html`);
  writeFileSync(cardPath, source);
  run(["cmd/tgc", "--", "card", cardPath, join(out, `${stem}.wasm`)]);
  const key = stem;
  const { manifest } = await loadGuest(
    readFileSync(join(out, `${stem}.wasm`)),
    key,
    { runtime },
  );
  return { key, manifest, guest: globalThis.__cardguest[key] };
}

const kit = await load(KIT, "compose-guest-kit");
const notes = await load(NOTES, "compose-guest-notes");

test("each module's components name the module that made them", () => {
  // Step one of the fix, and the one the other two rest on: without this an
  // instance cannot say where it came from, and `tg_inst.id` cannot stand in —
  // it is a per-module counter starting at zero, so two modules' first
  // instances share an id.
  for (const [m, want] of [
    [kit.manifest, "compose-guest-kit"],
    [notes.manifest, "compose-guest-notes"],
  ]) {
    assert.equal(m.moduleName, want);
    for (const c of m.components) assert.equal(c.module, want);
  }
});

test("two modules loaded together do not share a handle space", () => {
  // The inbound half, stated as the property rather than the symptom: if these
  // two collide then every `$dyn` marker is ambiguous and the rest of this file
  // is testing an accident.
  const a = kit.guest.create("Hole", JSON.stringify({ kept: "" }));
  const b = notes.guest.create("Note", JSON.stringify({ body: "x" }));
  assert.ok(a > 0 && b > 0);
  assert.notEqual(a, b);
});

test("a hole in one module holds a component from another", () => {
  const note = notes.guest.create("Note", JSON.stringify({ body: "from B" }));
  const hole = kit.guest.create(
    "Hole",
    JSON.stringify({ child: { $dyn: { handle: note } }, kept: "" }),
  );
  // Read THROUGH the child, which is what makes this a composition rather than
  // a value that happens to be stored: the compute is the kit's, the property
  // is the note's, and nothing in either card knows about the other.
  const shown = kit.guest.renderCall(
    hole,
    "compute",
    "innerBody",
    "[]",
    null,
  );
  assert.equal(JSON.parse(shown), "from B");
});

test("the instance a hole hands back is still the other module's", () => {
  // The outbound half. Reading the field returns the marker the host decodes to
  // wrap it again — and wrapping it with the READING module's schema is how a
  // note came back as a hole, with a hole's fields and a hole's view.
  const note = notes.guest.create("Note", JSON.stringify({ body: "round" }));
  const hole = kit.guest.create(
    "Hole",
    JSON.stringify({ child: { $dyn: { handle: note } }, kept: "" }),
  );
  const back = JSON.parse(kit.guest.getField(hole, "child"));
  assert.equal(back.$dyn.comp, "Note");
  assert.equal(back.$dyn.module, "compose-guest-notes");
  // And the handle it names still reaches the note, from either side.
  assert.equal(
    JSON.parse(notes.guest.getField(back.$dyn.handle, "body")),
    "round",
  );
});

///
/// The door `.child.x` goes through, and why it is the property one.
///
/// A holder holds components it did not write, so reading through the `get`
/// slot — the private field slot — would make every field of every component
/// legible to whoever happened to hold it. Op 8 and op 9 instead: the
/// declaration is the whole permission, and `secret` has none.
///
/// Both directions answered null before any of this, silently, which is how a
/// holder that changed nothing reported success by saying nothing at all.
test("a holder reaches only what the held component made public", () => {
  const note = notes.guest.create(
    "Note",
    JSON.stringify({ body: "public", secret: "private" }),
  );
  const hole = kit.guest.create(
    "Hole",
    JSON.stringify({ child: { $dyn: { handle: note } }, kept: "" }),
  );
  // Declared `property`: legible.
  assert.equal(
    JSON.parse(kit.guest.renderCall(hole, "compute", "innerBody", "[]", null)),
    "public",
  );
  // Declared as a field and nothing else: not legible, though the component
  // itself reads it perfectly well.
  //
  // `null` here is the null VALUE and not `ref.null`, which SPEC §9 is emphatic
  // are different things — the compute answers one because a compute has to
  // answer something, and its emitted body turns a member that read nothing
  // into `tg_null()`. The refusal that stays a refusal is the WRITE below,
  // where no successor is a real "this did not happen".
  assert.equal(
    JSON.parse(kit.guest.renderCall(hole, "compute", "innerSecret", "[]", null)),
    null,
  );
  assert.equal(JSON.parse(notes.guest.getField(note, "secret")), "private");
});

test("writing through a holder is copy on write, and refused where it is private", () => {
  const note = notes.guest.create(
    "Note",
    JSON.stringify({ body: "before", secret: "private" }),
  );
  const hole = kit.guest.create(
    "Hole",
    JSON.stringify({ child: { $dyn: { handle: note } }, kept: "" }),
  );
  const wrote = JSON.parse(
    kit.guest.dispatch(hole, "message", "rename", JSON.stringify(["after"]), null),
  );
  assert.equal(wrote.handled, true);
  const after = JSON.parse(kit.guest.getField(wrote.next, "child"));
  // A NEW handle: the note was not mutated, it was succeeded. The one the test
  // still holds says what it always said.
  assert.notEqual(after.$dyn.handle, note);
  assert.equal(JSON.parse(notes.guest.getField(after.$dyn.handle, "body")), "after");
  assert.equal(JSON.parse(notes.guest.getField(note, "body")), "before");

  // The private one is refused, and a refusal is no successor rather than a
  // successor that quietly kept the old value.
  const denied = JSON.parse(
    kit.guest.dispatch(hole, "message", "leak", JSON.stringify(["x"]), null),
  );
  assert.equal(denied.handled, false);
  assert.equal(JSON.parse(notes.guest.getField(note, "secret")), "private");
});
