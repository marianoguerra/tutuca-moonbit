// Two REAL modules, one tree, one click — the seam between the two proofs.
//
// `tgc/host/host_test.mbt` asks this with two in-process fakes and gets yes.
// `compose-guest.test.mjs` asks the bridge whether a component from one module
// can be held, read and written through another, and gets yes. Neither of them
// puts a COMPILED module's component inside another COMPILED module's field and
// then dispatches into it, which is what a page holding two cards does every
// time somebody clicks.
//
//   node --test tgc/test/twomod.test.mjs
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

run(["cmd/tgc", "--", "runtime", join(out, "twomod-rt.wasm")]);
const runtime = (
  await WebAssembly.instantiate(readFileSync(join(out, "twomod-rt.wasm")), {})
).instance.exports;

// The probe: `tgc/test/twomod`, which registers modules into ONE scope, mounts
// on the in-memory DOM, and clicks. Built as a js executable because that is
// the only place `tgc/emit`, `card.js`, `tutucard/guest` and the app all meet.
execFileSync("moon", ["build", "--target", "js", "tgc/test/twomod"], {
  cwd: process.cwd(),
  stdio: "inherit",
});
(0, eval)(
  readFileSync("_build/js/debug/build/tgc/test/twomod/twomod.js", "utf8"),
);
const probe = globalThis.__twomod;
assert.ok(probe, "the probe did not install globalThis.__twomod");

// The holder. `holds` is a bare `Instance`, so what goes in it is anybody's.
const KIT = `<script type="tutuca/spec">
  state Shelf { holds: Instance }
</script>
<script type="tutuca/script">
  receive hold(inst) { .holds = inst }
</script>
<template id="Shelf:main" data-root><div class="shelf"><x render=".holds"></x></div></template>
`;

// The stranger. An ordinary counter with an ordinary \`receive\`.
const OTHER = `<script type="tutuca/spec">
  state Counter { count: Int }
</script>
<script type="tutuca/script">
  receive inc { .count += 1 }
</script>
<template id="Counter:main" data-root><div class="counter"><button class="inc" @on.click="inc">+</button><output class="n" @text=".count"></output></div></template>
`;

async function load(source, stem) {
  const cardPath = join(out, `${stem}.html`);
  writeFileSync(cardPath, source);
  run(["cmd/tgc", "--", "card", cardPath, join(out, `${stem}.wasm`)]);
  const { manifest } = await loadGuest(
    readFileSync(join(out, `${stem}.wasm`)),
    stem,
    { runtime },
  );
  const answer = probe.register(stem, JSON.stringify(manifest));
  assert.equal(answer, "ok", `${stem}: ${answer}`);
  return manifest;
}

const kit = await load(KIT, "twomod-kit");
const other = await load(OTHER, "twomod-other");

test("the two modules are two modules", () => {
  assert.equal(kit.moduleName, "twomod-kit");
  assert.equal(other.moduleName, "twomod-other");
  assert.equal(kit.components[0].module, "twomod-kit");
  assert.equal(other.components[0].module, "twomod-other");
});

test("a compiled shelf renders a compiled counter from another module", () => {
  const html = probe.mount(
    "twomod-kit",
    "Shelf",
    "holds",
    "twomod-other",
    "Counter",
  );
  assert.ok(html.includes("shelf"), html);
  // The counter's OWN view, drawn inside the shelf's — which is the half that
  // was never in doubt.
  assert.ok(html.includes("counter"), html);
  assert.match(html, /class="n"[^>]*>0</);
});

test("…and it answers a click, through a holder that has never heard of it", () => {
  // THE ONE THAT MATTERS. The click has to reach a component the shelf could
  // not have built, and the successor has to be written back through a module
  // whose manifest does not mention it.
  const html = probe.click("button.inc");
  assert.match(html, /class="n"[^>]*>1</, html);
});

test("a hole filled by a MESSAGE holds it just as well", () => {
  // The path a placement actually takes. A page builds the hole first — it has
  // to, because the hole is what draws the `+` that asks — and what goes in it
  // arrives later, as an argument to a `receive`. That is a different crossing
  // from a construction argument, and the two had never been asked separately.
  const empty = probe.mountEmpty("twomod-kit", "Shelf");
  assert.ok(empty.includes("shelf"), empty);
  assert.ok(!empty.includes("counter"), empty);

  const filled = probe.hold("hold", "twomod-other", "Counter");
  assert.ok(filled.includes("counter"), filled);
  assert.match(filled, /class="n"[^>]*>0</);
});

test("…and THAT one answers a click too", () => {
  const html = probe.click("button.inc");
  assert.match(html, /class="n"[^>]*>1</, html);
});
