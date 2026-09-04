// The playground's guest bridge, driven with no page.
//
// `tutucard/web/card.js` installs the surface `cardguest.mbt` calls —
// `create`, `getField`, `dispatch`, `renderCall`, `withField` — over a `tgc`
// module. A browser is where it runs; this is where it is CHECKED, because a
// bridge only a page can exercise is a bridge nobody exercises.
//
//   node --test tgc/test/guest.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadGuest } from "../../tutucard/web/card.js";

const out = join(process.cwd(), "_build/tgc");
mkdirSync(out, { recursive: true });

const run = (args) =>
  execFileSync("moon", ["run", "--target", "native", ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
  });

// The runtime, built the way a page builds it: from the EMBEDDED source, so a
// stale `rt_src_gen.mbt` fails here rather than in a browser.
run(["cmd/tgc", "--", "runtime", join(out, "guest-rt.wasm")]);
const runtime = (
  await WebAssembly.instantiate(readFileSync(join(out, "guest-rt.wasm")), {})
).instance.exports;

const CARD = `<script type="tutuca/spec">
  struct Pane { inner: String }
  state Counter {
    count: Int, label: String, tags: Set[String]
    rows: Array[String], panes: Map[String, Pane]
  }
</script>
<script type="tutuca/script">
  receive inc { .count += 1 }
  receive setTo(n) { .count = n }
  receive tag(t) { .tags.add t }
  receive announce { send 'shouted' .label }
  receive poke(i) { sendAt &.rows[i] 'ping' 1 }
  receive pokeNamed(k) { sendAt &.panes[k].inner 'ping' }
  compute shown { $'count: {.count}' }
  pred big { .count > 2 }
</script>
<template id="Counter:main" data-root><b></b></template>
`;

async function mount() {
  // Compiled through the same entry point the playground calls.
  const cardPath = join(out, "guest-card.html");
  const { writeFileSync } = await import("node:fs");
  writeFileSync(cardPath, CARD);
  run(["cmd/tgc", "--", "card", cardPath, join(out, "guest-card.wasm")]);
  const bytes = readFileSync(join(out, "guest-card.wasm"));
  const key = `k${Math.random()}`;
  await loadGuest(bytes, key, { runtime });
  return globalThis.__cardguest[key];
}

const guest = await mount();

test("a card constructs, and its fields read back", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 2, label: "hi" }));
  assert.ok(h > 0);
  assert.equal(JSON.parse(guest.getField(h, "count")), 2);
  assert.equal(JSON.parse(guest.getField(h, "label")), "hi");
  // Absence is the empty string, which is how `cardguest.mbt` reads "no such
  // field" — distinct from a field holding null.
  assert.equal(guest.getField(h, "nope"), "");
});

test("a transition answers a successor and leaves its predecessor alone", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 2 }));
  const r = JSON.parse(guest.dispatch(h, 0, "inc", "[]", "{}"));
  assert.equal(r.handled, true);
  assert.ok(r.next > 0);
  assert.equal(JSON.parse(guest.getField(r.next, "count")), 3);
  assert.equal(JSON.parse(guest.getField(h, "count")), 2);
});

test("a name no arm answers produces no successor", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 2 }));
  const r = JSON.parse(guest.dispatch(h, 0, "nope", "[]", "{}"));
  assert.equal(r.handled, false);
  assert.equal(r.next, null);
});

test("arguments cross, and a set is a collection", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 0 }));
  const set = JSON.parse(guest.dispatch(h, 0, "setTo", "[7]", "{}"));
  assert.equal(JSON.parse(guest.getField(set.next, "count")), 7);
  const tagged = JSON.parse(guest.dispatch(h, 0, "tag", '["red"]', "{}"));
  assert.deepEqual(JSON.parse(guest.getField(tagged.next, "tags")), { red: true });
});

test("an effect is buffered by the host and comes back with the dispatch", () => {
  const h = guest.create("Counter", JSON.stringify({ label: "ada" }));
  const r = JSON.parse(guest.dispatch(h, 0, "announce", "[]", "{}"));
  assert.deepEqual(r.msgs, [{ kind: "send", name: "shouted", args: ["ada"] }]);
});

// `sendAt` names a POSITION, and which wire case a keyed step becomes is
// decided at RUN time — a whole non-negative number is an index, anything else
// is a key. The card cannot know which, because `.rows[k]` and `.panes[k]` are
// the same syntax.
test("sendAt reifies a place, and the key decides its own step", () => {
  const h = guest.create("Counter", JSON.stringify({}));
  const byIndex = JSON.parse(guest.dispatch(h, 0, "poke", "[2]", "{}"));
  assert.deepEqual(byIndex.msgs, [
    { kind: "sendAt", path: [{ at: ["rows", 2] }], name: "ping", args: [1] },
  ]);
  const byKey = JSON.parse(guest.dispatch(h, 0, "pokeNamed", '["left"]', "{}"));
  assert.deepEqual(byKey.msgs, [
    {
      kind: "sendAt",
      path: [{ item: ["panes", "left"] }, { field: "inner" }],
      name: "ping",
      args: [],
    },
  ]);
});

test("a compute answers its value and a pred answers truthiness", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 5 }));
  assert.equal(JSON.parse(guest.renderCall(h, "method", "shown", "[]", "{}")), "count: 5");
  assert.equal(JSON.parse(guest.renderCall(h, "when", "big", "[]", "{}")), true);
  const small = guest.create("Counter", JSON.stringify({ count: 1 }));
  assert.equal(JSON.parse(guest.renderCall(small, "when", "big", "[]", "{}")), false);
});

test("withField is the COW write-through a host path writes through", () => {
  const h = guest.create("Counter", JSON.stringify({ count: 1 }));
  const next = guest.withField(h, "count", "9");
  assert.ok(next > 0);
  assert.equal(JSON.parse(guest.getField(next, "count")), 9);
  assert.equal(JSON.parse(guest.getField(h, "count")), 1);
  // A field nothing declares has nowhere to go.
  assert.equal(guest.withField(h, "nope", "1"), -1);
});

///
/// The drift check.
///
/// `rt.wax` is authoritative and `rt_src_gen.mbt` is a copy of it that MoonBit
/// can reach. A stale copy compiles fine and is the WRONG RUNTIME, which a page
/// would discover as a link error a long way from the edit that caused it.
test("the embedded runtime is not stale against rt.wax", async () => {
  const { readFileSync, writeFileSync } = await import("node:fs");
  const path = join(process.cwd(), "tgc/rt/rt_src_gen.mbt");
  // Against the file as it stands rather than against a commit: what this
  // catches is `rt.wax` edited and the embed not rerun, which is true whether
  // or not either half has been committed yet.
  const before = readFileSync(path, "utf8");
  execFileSync("node", ["tgc/rt/embed.mjs"], { cwd: process.cwd() });
  const after = readFileSync(path, "utf8");
  if (before !== after) writeFileSync(path, before);
  assert.equal(
    after,
    before,
    "rt_src_gen.mbt is stale against rt.wax — run `cmd/dev -- rt-embed` and commit both halves",
  );
});
