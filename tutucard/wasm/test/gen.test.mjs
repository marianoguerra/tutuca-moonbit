// The generator, checked against the host's own canonical ABI.
//
// This is the test that matters, and it is deliberately the same harness
// `dyncomp/test/abi.test.mjs` uses on the shipped MoonBit guests: a compiled
// card is loaded through `dyncomp/host/wasm/abi.mjs` and driven. Nothing here
// knows how the module was produced, so what it proves is not "the generator
// emitted what the generator meant" but "the host accepts this as a
// tutuca:component@0.7.0 guest".
//
//   node --test tutucard/wasm/test/
//
// It shells out to `cmd/cardwasm` (native) once per card. That is slow the
// first time and cached afterwards, and it is what keeps the fixtures from
// being checked-in wasm nobody can regenerate.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { instantiate } from "../../../dyncomp/host/wasm/abi.mjs";

// The module root: `tutucard/wasm/test` -> up three.
const MODULE = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const out = mkdtempSync(join(tmpdir(), "cardwasm-"));

/** Compile one of `tutucard/wasm/examples/` and instantiate it. */
async function load(stem) {
  const log = execFileSync(
    "moon",
    [
      "run",
      "cmd/cardwasm",
      "--target",
      "native",
      "--",
      `tutucard/wasm/examples/${stem}.html`,
      out,
    ],
    { cwd: MODULE, encoding: "utf8" },
  );
  const descriptor = JSON.parse(
    readFileSync(join(out, `${stem}.descriptor.json`), "utf8"),
  );
  const wasm = readFileSync(join(out, `${stem}.wasm`));
  const control = [];
  // The value arena, the same shape `dyncomp/test/abi.test.mjs` gives the
  // shipped MoonBit guests. A card that declares a collection imports this
  // interface — `%list` and `%map` cross as u64 handles because WIT has no
  // recursive types — and one that declares only scalars does not, which is
  // what `arenaUsed` below is asserted on.
  const arena = new Map();
  let next = 1n;
  const put = (value) => {
    const handle = next++;
    arena.set(handle, value);
    return handle;
  };
  const root = await instantiate(
    () => WebAssembly.compile(wasm),
    {
      "tutuca:component/values": {
        listLen: (h) => arena.get(h).length,
        listGet: (h, i) => arena.get(h)[i],
        mapLen: (h) => arena.get(h).size,
        mapKeys: (h) => [...arena.get(h).keys()],
        mapGet: (h, k) => arena.get(h).get(k),
        listNew: () => put([]),
        listPush: (h, value) => arena.get(h).push(value),
        mapNew: () => put(new Map()),
        mapSet: (h, key, value) => arena.get(h).set(key, value),
        toJson: JSON.stringify,
        fromJson: JSON.parse,
      },
      "tutuca:component/control": {
        emit: (name, args) => control.push({ kind: "emit", name, args }),
        send: (name, args) => control.push({ kind: "send", name, args }),
        stopPropagation: () => control.push({ kind: "stop" }),
      },
    },
    { ...descriptor, core: `${stem}.wasm` },
  );
  return {
    root,
    control,
    log,
    arena,
    manifest: JSON.parse(readFileSync(join(out, `${stem}.manifest.json`), "utf8")),
    bytes: wasm.length,
  };
}

const num = (v) => ({ tag: "number", val: v });
const text = (v) => ({ tag: "text", val: v });

test("a compiled card is a guest the host ABI accepts", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", [["count", num(4)], ["step", num(3)]]);
  assert.deepEqual(c.getField("count"), num(4));
  assert.deepEqual(c.getField("step"), num(3));
  // A name the card does not declare is `none`, not a zero.
  assert.equal(c.getField("nope"), undefined);
  // …and a guest that does not persist says so with no bytes at all.
  assert.deepEqual(c.persist(), new Uint8Array());
  assert.equal(root.guest.Instance.restore("Counter", new Uint8Array()), undefined);
});

test("an unknown dispatch is unhandled, so the host can fall back", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", []);
  assert.deepEqual(c.handleEvent("input", "nope", []), { tag: "unhandled" });
  // Right name, wrong bucket: the buckets are separate dispatch spaces.
  assert.deepEqual(c.handleEvent("receive", "inc", []), { tag: "unhandled" });
});

test("a transition answers with a new instance, and a no-op with unchanged", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", [["count", num(4)], ["step", num(3)]]);
  const inc = c.handleEvent("input", "inc", []);
  assert.equal(inc.tag, "changed");
  assert.deepEqual(inc.val.getField("count"), num(7));
  // The predecessor is untouched: self in, self out.
  assert.deepEqual(c.getField("count"), num(4));
  const dec = inc.val.handleEvent("input", "dec", []);
  assert.deepEqual(dec.val.getField("count"), num(4));
  // `reset` on a count that is already zero changes nothing, and the guest
  // says so rather than handing back an equal instance with a new identity.
  const zero = c.withField("count", num(0));
  assert.deepEqual(zero.handleEvent("input", "reset", []), { tag: "unchanged" });
});

test("event arguments arrive as the declared parameters", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", []);
  const init = c.handleEvent("receive", "init", []);
  assert.deepEqual(init.val.getField("step"), num(1));
});

test("call-method serves computes and preds, and templates format numbers", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", [["count", num(4)]]);
  assert.deepEqual(c.callMethod("label", []), text("the count is 4"));
  assert.deepEqual(c.callMethod("positive", []), { tag: "boolean", val: true });
  assert.deepEqual(
    c.withField("count", num(0)).callMethod("positive", []),
    { tag: "boolean", val: false },
  );
  // Fractions to six digits with the trailing zeros trimmed, and a sign.
  assert.deepEqual(c.withField("count", num(2.5)).callMethod("label", []), text("the count is 2.5"));
  assert.deepEqual(c.withField("count", num(-17)).callMethod("label", []), text("the count is -17"));
  // A method the card does not declare is nil rather than a trap.
  assert.deepEqual(c.callMethod("nope", []), { tag: "nil" });
});

test("with-field round-trips every value shape, text included", async () => {
  const { root } = await load("Cart");
  const c = new root.guest.Instance("Cart", []);
  assert.deepEqual(c.withField("qty", num(41)).getField("qty"), num(41));
  assert.deepEqual(c.withField("price", num(2.5)).getField("price"), num(2.5));
  // utf8 in the guest, and a non-ASCII string is where a length in code units
  // and a length in bytes stop agreeing.
  assert.deepEqual(c.withField("item", text("héllo")).getField("item"), text("héllo"));
  assert.deepEqual(
    c.withField("sent", { tag: "boolean", val: true }).getField("sent"),
    { tag: "boolean", val: true },
  );
  // A field the card does not declare is refused, not invented.
  assert.equal(c.withField("nope", num(1)), undefined);
});

test("with-field refuses a value the field's declared type cannot hold", async () => {
  const { root } = await load("Cart");
  const c = new root.guest.Instance("Cart", []);
  // The schema decides. `qty` is an Int, so a string and a bool are refused
  // and the host falls back rather than being handed a successor whose state
  // disagrees with the schema it published.
  //
  // The cell runtime accepted both: `with-field` checked the NAME and then
  // wrote whatever joined payload it was handed into the cell, so a card could
  // end up with a text in an Int field and a view rendering it. Validation is
  // free here — `jv_record_try_set` was always going to run — and this is the
  // one place the new representation is stricter rather than merely wider.
  assert.equal(c.withField("qty", text("nope")), undefined);
  assert.equal(c.withField("qty", { tag: "boolean", val: true }), undefined);
  assert.equal(c.withField("item", num(1)), undefined);
  // And the instance it refused is untouched.
  assert.deepEqual(c.getField("qty"), num(0));
});

test("effects reach the host, and a precondition declines the transition", async () => {
  const { root, control } = await load("Cart");
  const c = new root.guest.Instance("Cart", [["qty", num(2)], ["price", num(3.5)]]);
  assert.deepEqual(c.callMethod("total", []), num(7));
  assert.deepEqual(c.callMethod("line", []), text("2 x  = 7"));
  // `requires hasItem` — no item, so nothing happens and nothing is emitted.
  assert.deepEqual(c.handleEvent("input", "checkout", []), { tag: "unchanged" });
  assert.deepEqual(control, []);

  const named = c.handleEvent("input", "rename", [text("coffee")]).val;
  assert.deepEqual(named.callMethod("line", []), text("2 x coffee = 7"));
  const out = named.handleEvent("input", "checkout", []);
  assert.equal(out.tag, "changed");
  assert.deepEqual(out.val.getField("sent"), { tag: "boolean", val: true });
  assert.deepEqual(control, [
    { kind: "emit", name: "lineReady", args: [text("coffee"), num(7)] },
    { kind: "stop" },
  ]);
});

test("`max` clamps, so the invariant holds without ever declining", async () => {
  const { root } = await load("Cart");
  const c = new root.guest.Instance("Cart", [["qty", num(1)]]);
  assert.deepEqual(c.handleEvent("input", "fewer", []).val.getField("qty"), num(0));
  // At zero the clamp is a no-op, which the byte comparison reports honestly.
  const zero = c.withField("qty", num(0));
  assert.deepEqual(zero.handleEvent("input", "fewer", []), { tag: "unchanged" });
});

test("a list field holds a list, and pushing to it compiles", async () => {
  const { root, log, manifest, arena } = await load("Cart");
  // A `%list` crosses as a u64 HANDLE into the arena the host owns — WIT has
  // no recursive types — so reading one back is two steps, and the second is
  // the host's own map.
  const listOf = (v) => {
    assert.equal(v.tag, "list");
    return arena.get(v.val);
  };
  // Both used to be refused, for the same reason: "a list has no cell
  // representation". `jv_value` has one.
  assert.doesNotMatch(log, /refused field history/);
  assert.doesNotMatch(log, /refused on remember/);

  const c = new root.guest.Instance("Cart", []);
  // An empty list, not a nil — the zero its declared type gives it.
  assert.deepEqual(listOf(c.getField("history")), []);

  // `on remember { .history.push .qty }`, three times over a changing qty.
  const one = c.withField("qty", num(2)).handleEvent("input", "remember", []).val;
  assert.deepEqual(listOf(one.getField("history")), [num(2)]);
  const two = one.withField("qty", num(5)).handleEvent("input", "remember", []).val;
  assert.deepEqual(listOf(two.getField("history")), [num(2), num(5)]);
  // The predecessor is untouched: a successor SHARES structure with it rather
  // than being a copy of it, which is the whole of tutuca's COW model and now
  // the whole of how the guest stores state.
  assert.deepEqual(listOf(one.getField("history")), [num(2)]);

  // The manifest projects the field as the list it is, so a host generating a
  // form or a JSON Schema against it sees a list rather than a hole.
  const cart = manifest.components[0];
  const history = cart.fields.find((f) => f.name === "history");
  assert.equal(cart.types[history.ty].kind, "ty-list");
  assert.deepEqual(cart.fields.map((f) => f.name), [
    "item",
    "qty",
    "price",
    "sent",
    "history",
    "receipt",
  ]);
});

test("the builtins that needed a collection or a string now compile", async () => {
  const { root, log } = await load("Cart");
  // `len`, `trim` and `empty?` over a real string and a real list. All six of
  // `len has contains lower upper trim` used to be refused together — none of
  // them needed anything but a value model that had a length.
  assert.doesNotMatch(log, /refused compute remembered/);
  assert.doesNotMatch(log, /refused compute tidy/);
  assert.doesNotMatch(log, /refused pred namable/);

  const c = new root.guest.Instance("Cart", []);
  assert.deepEqual(c.callMethod("remembered", []), num(0));
  const one = c.withField("qty", num(7)).handleEvent("input", "remember", []).val;
  assert.deepEqual(one.callMethod("remembered", []), num(1));

  // `trim` is exactly " \t\n\r", which is the `chars=` the interpreter passes.
  const spaced = c.withField("item", text("  cheese \n"));
  assert.deepEqual(spaced.callMethod("tidy", []), text("cheese"));
  assert.deepEqual(spaced.callMethod("namable", []), { tag: "boolean", val: true });
  assert.deepEqual(
    c.withField("item", text("   ")).callMethod("namable", []),
    { tag: "boolean", val: false },
  );
});

test("`new` builds a declared record, and `@cur` fills it before it is pushed", async () => {
  const { root, log, arena } = await load("Cart");
  // `new Line` used to be refused for having no constructor. It has one now:
  // the zero of a declared type is a property of the type, so the generator
  // resolves it and builds the value at compile time.
  assert.doesNotMatch(log, /refused on receipt/);

  const c = new root.guest.Instance("Cart", []);
  assert.deepEqual(arena.get(c.getField("receipt").val), []);

  const one = c
    .withField("item", text("cheese"))
    .withField("qty", num(2))
    .handleEvent("input", "receipt", []).val;
  const rows = arena.get(one.getField("receipt").val);
  assert.equal(rows.length, 1);
  assert.deepEqual(
    Object.fromEntries([...arena.get(rows[0].val)].map(([k, v]) => [k, v.val])),
    { what: "cheese", qty: 2 },
  );

  // A second `new` starts over rather than editing the first, which is what
  // makes the two rows two rows.
  const two = one
    .withField("item", text("bread"))
    .withField("qty", num(1))
    .handleEvent("input", "receipt", []).val;
  const rows2 = arena.get(two.getField("receipt").val);
  assert.equal(rows2.length, 2);
  assert.deepEqual(
    Object.fromEntries([...arena.get(rows2[0].val)].map(([k, v]) => [k, v.val])),
    { what: "cheese", qty: 2 },
  );
  assert.deepEqual(
    Object.fromEntries([...arena.get(rows2[1].val)].map(([k, v]) => [k, v.val])),
    { what: "bread", qty: 1 },
  );
});

test("a card with only scalar fields does not import the value arena", async () => {
  // The import section is what a host inspects to know what a guest can do, so
  // the arena is imported by the cards that can produce a compound value and
  // by no others. Counter is four scalars; Cart declares `history`.
  const counter = readFileSync(join(out, "Counter.wasm"));
  const cart = readFileSync(join(out, "Cart.wasm"));
  const imports = (bytes) =>
    WebAssembly.Module.imports(new WebAssembly.Module(bytes)).map((i) => i.module);
  assert.ok(!imports(counter).some((m) => m.includes("values")));
  assert.ok(imports(cart).some((m) => m.includes("values")));
});

test("a compute may call another, and an invariant guards every transition", async () => {
  const { root } = await load("Temperature");
  const t = new root.guest.Instance("Temperature", [["c", num(20)]]);
  assert.deepEqual(t.callMethod("f", []), num(68));
  // `both` interpolates `f`, which reads the same state it does.
  assert.deepEqual(t.callMethod("both", []), text("20 °C is 68 °F"));
  assert.deepEqual(
    t.handleEvent("input", "warmer", []).val.callMethod("both", []),
    text("21 °C is 69.8 °F"),
  );
  // `invariant physical { .c >= -273.15 }` — asked of the SUCCESSOR, so the
  // step that would cross absolute zero simply does not happen.
  assert.deepEqual(
    t.withField("c", num(-273)).handleEvent("input", "cooler", []),
    { tag: "unchanged" },
  );
  assert.equal(
    t.withField("c", num(-272)).handleEvent("input", "cooler", []).tag,
    "changed",
  );
});

test("the whole module stays small enough to be worth compiling in a page", async () => {
  const { bytes } = await load("Counter");
  // Not a benchmark — a tripwire. An order of magnitude past this means
  // something is being emitted per declaration that should be emitted once.
  //
  // Re-baselined from 16 KB when the Wax data stdlib landed. ~37 KB of that is
  // the stdlib itself — a HAMT, a persistent vector, validated UTF-8 strings
  // and a runtime record system — and it is a FLOOR, not a slope: Wax's
  // emitter does no dead-code elimination, so every card carries all of it
  // whether or not it builds a list. The card's own code is still hundreds of
  // bytes, which is what this tripwire is actually watching; `gen/stdlib_test.mbt`
  // watches the floor separately, so a regression tells you which half moved.
  assert.ok(bytes < 56 * 1024, `core module is ${bytes} bytes`);
});
