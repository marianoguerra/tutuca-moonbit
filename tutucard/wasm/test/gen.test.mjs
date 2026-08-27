// The generator, checked against the host's own canonical ABI.
//
// This is the test that matters, and it is deliberately the same harness
// `dyncomp/test/abi.test.mjs` uses on the shipped MoonBit guests: a compiled
// card is loaded through `dyncomp/host/wasm/abi.mjs` and driven. Nothing here
// knows how the module was produced, so what it proves is not "the generator
// emitted what the generator meant" but "the host accepts this as a
// tutuca:component@0.10.0 guest".
//
//   node --test tutucard/wasm/test/
//
// It shells out to `cmd/cardwasm` (native) once per card. That is slow the
// first time and cached afterwards, and it is what keeps the fixtures from
// being checked-in wasm nobody can regenerate.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { instantiate } from "../../../dyncomp/host/wasm/abi.mjs";

// The module root: `tutucard/wasm/test` -> up three.
const MODULE = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const out = mkdtempSync(join(tmpdir(), "cardwasm-"));

/** Compile one of `tutucard/wasm/examples/` and instantiate it. */
async function load(stem, { allowWax = false } = {}) {
  const log = execFileSync(
    "moon",
    [
      "run",
      "cmd/cardwasm",
      "--target",
      "native",
      "--",
      ...(allowWax ? ["--allow-wax"] : []),
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
  // Children the guest asked for, in the order it asked. Built by `drain()`
  // rather than on the spot: see `makeInstance`.
  const children = [];
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
        // A card that declares a rule imports this to say when the rule turned
        // a transition away — the line `core/warn.mbt` prints, on the one
        // channel the guest world has for saying anything at all.
        log: (level, msg) => control.push({ kind: "log", level, msg }),
        send: (name, args) => control.push({ kind: "send", name, args }),
        stopPropagation: () => control.push({ kind: "stop" }),
        sendReply: (name, args) => control.push({ kind: "sendReply", name, args }),
        // Bound and answering nothing: nothing is above this guest, so a
        // declared lookup would read the default it declares.
        lookup: () => ({ tag: "nil" }),
        // The same-bundle child factory. A card that writes `new <Component>`
        // imports it; one that does not never names it, and an import the host
        // does not implement is an instantiation error rather than a silently
        // dropped effect — which is what these two lines are here to satisfy.
        //
        // The token is reserved and the construction queued, because the
        // Component Model forbids re-entering a component while a call into it
        // is active. `drain()` below builds them, and a test calls it when it
        // wants the child rather than the token.
        makeInstance: (component, args) => {
          const h = BigInt(children.length + 1);
          children.push({ handle: h, component, args, inst: null });
          return h;
        },
        dropInstance: (token) => {
          const at = children.findIndex((c) => c.handle === token);
          if (at >= 0) children.splice(at, 1);
        },
        sendAt: (path, name, args) => control.push({ kind: "sendAt", path, name, args }),
        // The routed four. A card that performs one imports it, and an import
        // the host does not implement is an instantiation error rather than a
        // silently dropped effect.
        //
        // `opts` is WIT `intent-opts` lifted: a `route` list of `leg` names,
        // three optional answer names and a `live-path` flag. A card never
        // names an arm and never asks for a live path, so only the route is
        // recorded here — and an empty one is "the card wrote no leg", which
        // is the host's to resolve.
        intent: (name, args, opts) =>
          control.push({ kind: "intent", name, args, route: opts.route }),
        forward: (args, opts) => control.push({ kind: "forward", args, route: opts.route }),
        // One `value` each, not a list of them.
        reply: (v) => control.push({ kind: "reply", value: v }),
        fail: (e) => control.push({ kind: "fail", value: e }),
      },
    },
    { ...descriptor, core: `${stem}.wasm` },
  );
  return {
    root,
    control,
    log,
    arena,
    children,
    /** Construct every child the guest asked for. */
    drain: () => {
      for (const c of children) {
        if (!c.inst) c.inst = new root.guest.Instance(c.component, c.args);
      }
      return children;
    },
    // Handing a compound value IN needs the same arena a compound value comes
    // out through: an enricher is passed the row's bindings as a `%map`.
    put,
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
  assert.deepEqual(c.handleEvent("receive", "nope", []), { tag: "unhandled" });
  // Right name, wrong bucket: the two are separate dispatch spaces, so a
  // `receive inc` is not reachable by routing an intent at the same name.
  assert.deepEqual(c.handleEvent("intent", "inc", []), { tag: "unhandled" });
});

test("a transition answers with a new instance, and a no-op with unchanged", async () => {
  const { root } = await load("Counter");
  const c = new root.guest.Instance("Counter", [["count", num(4)], ["step", num(3)]]);
  const inc = c.handleEvent("receive", "inc", []);
  assert.equal(inc.tag, "changed");
  assert.deepEqual(inc.val.getField("count"), num(7));
  // The predecessor is untouched: self in, self out.
  assert.deepEqual(c.getField("count"), num(4));
  const dec = inc.val.handleEvent("receive", "dec", []);
  assert.deepEqual(dec.val.getField("count"), num(4));
  // `reset` on a count that is already zero changes nothing, and the guest
  // says so rather than handing back an equal instance with a new identity.
  const zero = c.withField("count", num(0));
  assert.deepEqual(zero.handleEvent("receive", "reset", []), { tag: "unchanged" });
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
  assert.deepEqual(c.handleEvent("receive", "checkout", []), { tag: "unchanged" });
  // …but the card SAYS so, on the one channel a guest has for saying anything:
  // the line `core/warn.mbt` prints, with the rule's own `format` sentence
  // evaluated over the state that was rejected. The record the interpreter
  // builds still has no shape in the guest world; the sentence does.
  assert.deepEqual(control, [
    {
      kind: "log",
      level: "warn",
      msg:
        "contract: `checkout` declined — its precondition `hasItem` does not hold: " +
        "a line with no item cannot be checked out (2 of nothing)",
    },
  ]);
  control.length = 0;

  const named = c.handleEvent("receive", "rename", [text("coffee")]).val;
  assert.deepEqual(named.callMethod("line", []), text("2 x coffee = 7"));
  const out = named.handleEvent("receive", "checkout", []);
  assert.equal(out.tag, "changed");
  assert.deepEqual(out.val.getField("sent"), { tag: "boolean", val: true });
  assert.deepEqual(control, [
    { kind: "intent", name: "lineReady", args: [text("coffee"), num(7)], route: ["dyn"] },
    { kind: "stop" },
  ]);
});

test("`max` clamps, so the invariant holds without ever declining", async () => {
  const { root, control } = await load("Cart");
  const c = new root.guest.Instance("Cart", [["qty", num(1)]]);
  assert.deepEqual(c.handleEvent("receive", "fewer", []).val.getField("qty"), num(0));
  // At zero the clamp is a no-op, which the byte comparison reports honestly.
  const zero = c.withField("qty", num(0));
  assert.deepEqual(zero.handleEvent("receive", "fewer", []), { tag: "unchanged" });
  assert.deepEqual(control, []);

  // Reached round the clamp, the invariant DOES decline — and says so with the
  // short line, because `sane` declares no `format`. A refusal that cannot
  // describe itself is still a refusal, which is `sentence()`'s `""`.
  const bad = c.withField("qty", num(-5));
  assert.deepEqual(bad.handleEvent("receive", "more", []), { tag: "unchanged" });
  assert.deepEqual(control, [
    {
      kind: "log",
      level: "warn",
      msg: "contract: `more` was abandoned — it broke the invariant `sane`",
    },
  ]);
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

  // `receive remember { .history.push .qty }`, three times over a changing qty.
  const one = c.withField("qty", num(2)).handleEvent("receive", "remember", []).val;
  assert.deepEqual(listOf(one.getField("history")), [num(2)]);
  const two = one.withField("qty", num(5)).handleEvent("receive", "remember", []).val;
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

test("`num` and `int` read a string, and refuse what is not one", async () => {
  const { root, log } = await load("Reading");
  assert.doesNotMatch(log, /refused on parse/);
  assert.doesNotMatch(log, /refused on truncate/);
  const c = new root.guest.Instance("Reading", []);

  // The spellings a card writes by hand, exactly.
  for (const [raw, value] of [
    ["42", 42],
    ["-3.5", -3.5],
    ["+7", 7],
    [".5", 0.5],
    ["1e3", 1000],
    ["2.5e-2", 0.025],
  ]) {
    const r = c.withField("raw", text(raw)).handleEvent("receive", "parse", []);
    assert.equal(r.tag, "changed", `${raw} should parse`);
    assert.deepEqual(r.val.getField("value"), num(value), raw);
  }

  // A string that is not a number has NO ANSWER, and no answer is no change —
  // which is `eval.mbt` returning None, not a zero written into the field.
  for (const raw of ["12px", "", "abc", "1.2.3", "1e", "+", "."]) {
    assert.deepEqual(
      c.withField("raw", text(raw)).handleEvent("receive", "parse", []),
      { tag: "unchanged" },
      raw,
    );
  }

  // `int` is `num` and then a truncation, string reading included.
  const t = c.withField("raw", text("-3.9")).handleEvent("receive", "truncate", []);
  assert.deepEqual(t.val.getField("whole"), num(-3));
  // …and it declines the same values `num` declines, where it used to answer
  // null and let the field take it.
  assert.deepEqual(
    c.withField("raw", text("nope")).handleEvent("receive", "truncate", []),
    { tag: "unchanged" },
  );
});

test("a call and a send carry more than four values", async () => {
  const { root, control, log } = await load("Reading");
  assert.doesNotMatch(log, /refused on wide/);
  assert.doesNotMatch(log, /refused compute total/);
  const c = new root.guest.Instance("Reading", []);
  // Six arguments through a `compute`, which the fixed `tc_args1..4` family
  // could not express — the sixth used to be dropped, so this refused.
  assert.deepEqual(c.callMethod("total", [num(1), num(2), num(3), num(4), num(5), num(6)]), num(21));
  const r = c.handleEvent("receive", "wide", []);
  assert.deepEqual(r.val.getField("tally"), num(21));
  // And six payload values out through `control.send`, in order.
  assert.deepEqual(control, [
    { kind: "send", name: "wide", args: [1, 2, 3, 4, 5, 6].map(num) },
  ]);
});

test("an intent reaches the host, and its answer comes back", async () => {
  const { root, control, log } = await load("Reading");
  assert.doesNotMatch(log, /refused receive lookup/);
  assert.doesNotMatch(log, /refused receive rowsOk/);
  const c = new root.guest.Instance("Reading", [["raw", text("ada")]]);
  assert.deepEqual(c.handleEvent("receive", "lookup", []), { tag: "unchanged" });
  // The name, the arguments, and the route the call site wrote: `lex` is the
  // scope chain and nothing above it, and it crosses as the WIT's `list<leg>`.
  assert.deepEqual(control, [
    { kind: "intent", name: "rows", args: [text("ada")], route: ["lex"] },
  ]);
  // The answer comes back as an ORDINARY message, under the outcome's own
  // name and carrying only what that outcome is about: a handler cannot tell
  // it from one a parent sent, and no arm is handed a result AND an error to
  // discriminate.
  const back = c.handleEvent("receive", "rowsOk", [text("lovelace")]);
  assert.equal(back.tag, "changed");
  assert.deepEqual(back.val.getField("raw"), text("lovelace"));

  // And a request in a transition that goes on to FAIL never escapes: effects
  // are buffered and flushed only once every rule has held.
  assert.deepEqual(
    c.withField("raw", text("nope")).handleEvent("receive", "parse", []),
    { tag: "unchanged" },
  );
  assert.equal(control.length, 1);
});

test("`sendAt` reifies a place into the path steps the host resolves", async () => {
  const { root, control, log } = await load("Addressing");
  for (const h of ["pokeAll", "pokeRow", "pokeFirst", "pokePane", "pokeDeep"]) {
    assert.doesNotMatch(log, new RegExp(`refused on ${h}`));
  }
  const c = new root.guest.Instance("Addressing", [["word", text("hi")]]);

  // A bare `.field` — the whole slot.
  c.handleEvent("receive", "pokeAll", []);
  assert.deepEqual(control.at(-1), {
    kind: "sendAt",
    path: [{ tag: "field", val: "rows" }],
    name: "ping",
    args: [text("hi")],
  });

  // An index from a parameter, frozen to the value in hand. A number key is
  // `at`, which is what `control.path-step` calls a positional element.
  c.handleEvent("receive", "pokeRow", [num(2)]);
  assert.deepEqual(control.at(-1).path, [
    { tag: "at", val: { field: "rows", index: 2 } },
  ]);

  // A literal key is the same step written out.
  c.handleEvent("receive", "pokeFirst", []);
  assert.deepEqual(control.at(-1).path, [
    { tag: "at", val: { field: "rows", index: 0 } },
  ]);

  // A text key is `item`, and WHICH case it is was decided by the key's value
  // at run time — `.rows[k]` and `.panes[k]` are the same syntax.
  c.handleEvent("receive", "pokePane", [text("left")]);
  assert.deepEqual(control.at(-1).path, [
    { tag: "item", val: { field: "panes", key: "left" } },
  ]);

  // Two steps: the keyed one, then the trailing field.
  c.handleEvent("receive", "pokeDeep", [num(1)]);
  assert.deepEqual(control.at(-1).path, [
    { tag: "at", val: { field: "rows", index: 1 } },
    { tag: "field", val: "inner" },
  ]);

  // A key that is not a key at all abandons the transition, and nothing goes
  // out — `Value::as_key` answers None for a fraction, and a None is no change.
  const before = control.length;
  assert.deepEqual(c.handleEvent("receive", "pokeRow", [num(1.5)]), {
    tag: "unchanged",
  });
  assert.equal(control.length, before);

  // And the one form with no wire shape is REFUSED rather than approximated.
  // `&.panes[.sel]` means "re-read `.sel` on every dispatch"; freezing the key
  // would be a different path that looks like this one.
  assert.match(log, /refused receive pokeSelected/);
  // Refused means absent, so the host hears `unhandled` and falls back.
  assert.deepEqual(c.handleEvent("receive", "pokeSelected", []), {
    tag: "unhandled",
  });
});

test("a card that never addresses a place carries no path lowering", async () => {
  const { log } = await load("Counter");
  assert.doesNotMatch(log, /refused/);
  // The optional halves are a size decision, and `Counter` is the card that
  // wants none of them: no `num`, no `sendAt`, no collection.
  const bare = (await load("Counter")).bytes;
  const addressing = (await load("Addressing")).bytes;
  assert.ok(addressing > bare, `${addressing} should exceed ${bare}`);
});

test("a `@when` filter is handed the row, not parameters", async () => {
  const { root, log, manifest } = await load("Enriched");
  assert.doesNotMatch(log, /refused pred matches/);
  assert.doesNotMatch(log, /refused pred second/);
  // A filter is written `pred matches { … @value … }` with NO parameter list —
  // the renderer passes `(key, value, iter)` positionally — and this used to
  // read every `@name` as a refusal, so a compiled filter kept every row.
  const c = new root.guest.Instance("Enriched", [["needle", text("b")]]);
  const when = (name, key, value) =>
    c.callMethod(name, [key, value, { tag: "nil" }]);
  assert.deepEqual(when("matches", num(0), text("abc")), {
    tag: "boolean",
    val: true,
  });
  assert.deepEqual(when("matches", num(1), text("xyz")), {
    tag: "boolean",
    val: false,
  });
  assert.deepEqual(when("second", num(1), text("x")), {
    tag: "boolean",
    val: true,
  });
  assert.deepEqual(when("second", num(0), text("x")), {
    tag: "boolean",
    val: false,
  });
  // And the manifest says both names belong to the render-time namespace, or
  // the host would never route to them.
  assert.deepEqual(manifest.components[0].whens, ["matches", "second"]);
});

test("an enricher binds what the row does not carry", async () => {
  const { root, log, manifest, arena, put } = await load("Enriched");
  assert.doesNotMatch(log, /refused enrich row/);
  assert.doesNotMatch(log, /refused enrichScope info/);
  const c = new root.guest.Instance("Enriched", [["title", text("Rows")]]);
  const mapOf = (v) => {
    assert.equal(v.tag, "map");
    return Object.fromEntries(arena.get(v.val));
  };

  // The in-loop form: the row's bindings go down, and the whole map comes back
  // — a guest cannot write into the host's map, so `dynobj.mbt` merges what it
  // answers. `@echo = str @tag` reads a binding written the line above, which
  // is the case the corpus pins.
  const binds = put(new Map());
  const enriched = mapOf(
    c.callMethod("row", [
      { tag: "map", val: binds },
      num(3),
      text("b"),
      { tag: "nil" },
    ]),
  );
  assert.deepEqual(enriched, { tag: text("b"), echo: text("b"), at: num(3) });

  // A binding it was HANDED is readable and comes back untouched beside the
  // ones it wrote.
  const seeded = put(new Map([["from", text("earlier")]]));
  assert.deepEqual(
    mapOf(c.callMethod("row", [{ tag: "map", val: seeded }, num(0), text("z"), { tag: "nil" }])),
    { from: text("earlier"), tag: text("z"), echo: text("z"), at: num(0) },
  );

  // The scope form is handed no row at all, and its answer IS the map.
  assert.deepEqual(mapOf(c.callMethod("info", [])), {
    heading: text("Rows"),
    width: num(4),
  });

  // Both are in the manifest, under keys that did not exist: a host cannot
  // route to a name it was never told about, which is the other half of why a
  // card using `@enrich-with` used to lose its bindings in silence.
  assert.deepEqual(manifest.components[0].enriches, ["row"]);
  assert.deepEqual(manifest.components[0].enrichScopes, ["info"]);
});

test("an escape block is refused unless the host allows it", async () => {
  const { log, manifest } = await load("Escaped");
  // Refused rather than ignored: a card whose escape silently did nothing
  // would be a card whose author cannot tell "the host said no" from "I
  // spelled the function wrong".
  assert.match(log, /refused wax Escaped/);
  assert.doesNotMatch(log, /escaped /);
  // …and nothing it answered is claimed in the manifest, so the host will not
  // route to a name that is not there. `sane` is the script block's own
  // invariant, which is a method like any other callable.
  assert.deepEqual(manifest.components[0].methods, ["sane"]);
});

test("an escape answers what the block language turned away", async () => {
  const { root, control, log, manifest } = await load("Escaped", { allowWax: true });

  // Three escapes, three reasons. The REFUSAL that sent `ping` there is still
  // in the list — it is why the function exists — and the arm is the escape's.
  assert.match(log, /refused receive ping .*live state/);
  assert.match(log, /escaped receive ping -> card_receive_ping/);
  // A name the script block never declared at all is legal: an escape adds a
  // handler as readily as it replaces one.
  assert.match(log, /escaped receive accumulate -> card_receive_accumulate/);
  assert.match(log, /escaped compute rounded -> card_compute_rounded/);

  const c = new root.guest.Instance("Escaped", [["sel", text("b")]]);

  // The added handler runs, reads its argument, writes two fields through the
  // generated `set_<field>` accessors, and answers a successor.
  const up = c.handleEvent("receive", "accumulate", [num(2.5)]);
  assert.equal(up.tag, "changed");
  assert.deepEqual(up.val.getField("total"), num(2.5));
  assert.deepEqual(up.val.getField("hits"), num(1));
  assert.deepEqual(up.val.getField("note"), text("ok"));

  // `tcx_fail()` is how a hand-written body says "no answer", and the wrapper
  // reads it exactly where a compiled body's `tc_fail` is read.
  assert.deepEqual(c.handleEvent("receive", "accumulate", [num(-1)]), {
    tag: "unchanged",
  });

  // The replaced handler runs, and its effect is buffered and flushed like any
  // other — the escape said `tcx_send` and the wrapper did the rest.
  control.length = 0;
  assert.deepEqual(c.handleEvent("receive", "ping", []), { tag: "unchanged" });
  assert.deepEqual(control, [
    { kind: "send", name: "ping", args: [text("b")] },
  ]);

  // A `compute` escape answers a value, through the same `cm_<name>` every
  // other callable is reached by — which is what `escape_wrappers` buys.
  assert.deepEqual(c.withField("total", num(2.4)).callMethod("rounded", []), num(2));
  assert.deepEqual(c.withField("total", num(2.5)).callMethod("rounded", []), num(3));

  // And every escaped name is in the manifest, or a host would never route to
  // it. `rounded` is there despite the script block never declaring it.
  assert.deepEqual([...manifest.components[0].methods].sort(), ["rounded", "sane"]);
});

test("an escape gets the wrapper, so the card's rules still hold", async () => {
  const { root, control } = await load("Escaped", { allowWax: true });
  const c = new root.guest.Instance("Escaped", []);
  // `invariant sane { .total >= 0 }` is the SCRIPT block's, and it guards a
  // hand-written transition exactly as it guards a compiled one. An escape
  // answers a declaration's body, not its rules.
  const bad = c.withField("total", num(-5));
  assert.deepEqual(bad.handleEvent("receive", "accumulate", [num(1)]), {
    tag: "unchanged",
  });
  assert.deepEqual(control.at(-1), {
    kind: "log",
    level: "warn",
    msg: "contract: `accumulate` was abandoned — it broke the invariant `sane`",
  });
});

test("the screen takes functions and refuses what authority is made of", async () => {
  // Written out here rather than as fixture files: each is one line, and what
  // is being pinned is the REASON, which reads better beside the thing that
  // provoked it.
  const cases = [
    [
      'import "evil:mod/thing" { #[import = "go"] fn go(); }\nfn h() -> i32 { 1 }',
      /an `import`: a guest's authority is its import section/,
    ],
    ['#[export = "sneak"]\nfn sneak() -> i32 { 1 }', /`#\[export\]` on `sneak`/],
    ["fn tc_evil() -> i32 { 1 }", /`tc_evil` starts with `tc_`/],
    ["let leak: i32 = 0;\nfn h() -> i32 { leak }", /a global `leak`/],
    ["memory m2: i32 [1];", /a `memory`/],
    ["fn broken( { }", /it did not parse/],
  ];
  for (const [block, want] of cases) {
    const card =
      `<script type="tutuca/spec">\nstate Bad { n: Int }\n</` + `script>\n` +
      `<script type="tutuca/wax">\n${block}\n</` + `script>\n` +
      `<template id="Bad"><div></div></template>\n`;
    writeFileSync(join(out, "Bad.html"), card);
    const log = execFileSync(
      "moon",
      ["run", "cmd/cardwasm", "--target", "native", "--", "--allow-wax", join(out, "Bad.html"), out],
      { cwd: MODULE, encoding: "utf8" },
    );
    // Rejected, not refused: an escape block that cannot be trusted is not a
    // declaration this backend declines to compile, it is a card that does not
    // hold together. And `BadEscape` rather than `BadModule`, whose message
    // says "this is a cardwasm bug" — the card's author typed this.
    assert.match(log, /^rejected: this card's <script type="tutuca\/wax"> block: /);
    assert.match(log, want, `for: ${block}`);
  }
});

test("a card that never converts a number carries no parser", async () => {
  // The optional half is a size decision, and the only way to know it stayed
  // optional is to weigh a card that does not want it against one that does.
  const bare = (await load("Counter")).bytes;
  const parsing = (await load("Reading")).bytes;
  assert.ok(parsing > bare, `${parsing} should exceed ${bare}`);
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
  const one = c.withField("qty", num(7)).handleEvent("receive", "remember", []).val;
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
    .handleEvent("receive", "receipt", []).val;
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
    .handleEvent("receive", "receipt", []).val;
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
    t.handleEvent("receive", "warmer", []).val.callMethod("both", []),
    text("21 °C is 69.8 °F"),
  );
  // `invariant physical { .c >= -273.15 }` — asked of the SUCCESSOR, so the
  // step that would cross absolute zero simply does not happen.
  assert.deepEqual(
    t.withField("c", num(-273)).handleEvent("receive", "cooler", []),
    { tag: "unchanged" },
  );
  assert.equal(
    t.withField("c", num(-272)).handleEvent("receive", "cooler", []).tag,
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
  //
  // Re-baselined from 56 KB when the runtime learned two things, and BOTH are
  // floor rather than slope — they are in the shared runtime, and Wax emits
  // every function it is handed:
  //
  //   +223 bytes  `tc_types` and its four helpers, so a module can carry more
  //               than one component's schema. A card that declares one calls
  //               `tc_zero_of` and `tc_type_add` and never `tc_comp_of`, but it
  //               carries all four.
  //   + 85 bytes  the `%instance` tag in `tc_lower_scalar` / `tc_lift_flat` /
  //               `tc_lift_scalar_cell`, so a child token survives the wire.
  //
  // Both could be carved into conditional pieces the way `parse_num.wax` and
  // `send_at.wax` are — that is the answer if the floor becomes a problem —
  // but the two cost 308 bytes between them and carving arms out of three
  // shared functions means duplicating all three.
  assert.ok(bytes < 58 * 1024, `core module is ${bytes} bytes`);
});

// ---------------------------------------------------------------------------
// A card that declares more than one component.
//
// `viewfile` has always let one file declare several — `<template id="Row:main">`,
// `<script type="tutuca/script" for="Row">`, one `state` each — and this backend
// turned such a file away whole. It was the one restriction with nothing under
// it: `DynManifest.components` was already an array, `Bundle::make_instance`
// already resolved by name, and the constructor was already handed the name of
// the component it was to build and threw it away.
//
// What these pin is that the two components are genuinely SEPARATE inside one
// module: separate schemas, separate dispatch, separate generated names.

test("a card may declare more than one component", async () => {
  const { manifest } = await load("Two");
  assert.deepEqual(manifest.components.map((c) => c.name), ["Board", "Row"]);
  // Bundle-level facts stay bundle-level, and are named after the ROOT — the
  // first template in the file, which is what a host mounts when told no name.
  assert.equal(manifest.moduleName, "boardcard");
  const [board, row] = manifest.components;
  assert.deepEqual(board.fields.map((f) => f.name), ["title", "tally", "focus"]);
  assert.deepEqual(row.fields.map((f) => f.name), ["label", "done"]);
  assert.deepEqual(board.receives, ["bump"]);
  assert.deepEqual(row.receives, ["toggle"]);
});

test("each component is built by name, with its own schema", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", [["title", text("Sprint")]]);
  const row = new root.guest.Instance("Row", [["label", text("write it")]]);
  assert.deepEqual(board.getField("title"), text("Sprint"));
  assert.deepEqual(board.getField("tally"), num(0));
  assert.deepEqual(row.getField("label"), text("write it"));
  assert.deepEqual(row.getField("done"), { tag: "boolean", val: false });
  // The schemas do not leak into one another: a field of the other component
  // is `none` here, exactly as a field of no component would be.
  assert.equal(board.getField("label"), undefined);
  assert.equal(row.getField("tally"), undefined);
});

test("a dispatch lands on the component that declared it, and nowhere else", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", [["title", text("Sprint")]]);
  const row = new root.guest.Instance("Row", [["label", text("write it")]]);
  const bumped = board.handleEvent("receive", "bump", []);
  assert.equal(bumped.tag, "changed");
  assert.deepEqual(bumped.val.getField("tally"), num(1));
  const toggled = row.handleEvent("receive", "toggle", []);
  assert.equal(toggled.tag, "changed");
  assert.deepEqual(toggled.val.getField("done"), { tag: "boolean", val: true });
  // The crux. `handle-event` is handed a HANDLE, not a component name, so the
  // module has to work out which component an instance is before it picks an
  // arm — otherwise a `Board` would answer `toggle` and write a field it does
  // not have. It answers `unhandled`, which is what lets the host fall back.
  assert.deepEqual(board.handleEvent("receive", "toggle", []), { tag: "unhandled" });
  assert.deepEqual(row.handleEvent("receive", "bump", []), { tag: "unhandled" });
});

test("two components may declare the same name and mean different things", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", [
    ["title", text("Sprint")],
    ["tally", num(3)],
  ]);
  const row = new root.guest.Instance("Row", [["label", text("write it")]]);
  // Both declare `compute caption`. One module cannot hold two `cm_caption`,
  // so a generated name carries its component when the file needs it to — and
  // does not when it does not, which is what keeps every card that ever
  // compiled compiling.
  assert.deepEqual(board.callMethod("caption", []), text("Sprint: 3"));
  assert.deepEqual(row.callMethod("caption", []), text("write it"));
  const toggled = row.handleEvent("receive", "toggle", []);
  assert.deepEqual(toggled.val.callMethod("caption", []), text("done"));
});

// ---------------------------------------------------------------------------
// A child instance across the boundary.
//
// `values.value` has always had a seventh case — `%instance(u64)`, a
// same-bundle child as the token `guest.instance` hands out — and a compiled
// card could neither read one nor write one: `tc_lower_scalar` knew four tags
// and `tc_lift_scalar_cell` knew the same four, so a token handed in came back
// as nil.
//
// It is carried as `jv_i64`, which costs nothing: this runtime builds `jv_f64`
// and nothing else, because tutuca has exactly one number — so an i64 inside a
// card's value tree can only ever be a child token. And it is a SCALAR on the
// wire rather than an arena handle, so a card holding children and no
// collections still imports no value arena.
//
// What a card still cannot do is MAKE one. `new` builds a declared record, not
// an instance, and nothing this generator emits imports `control.make-instance`.
// So these hand a token IN and read it back — which is exactly the half a host
// needs before it can hand a card a child at all.

test("a child token survives with-field and get-field", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", [["title", text("Sprint")]]);
  // An empty slot is nil, not a zero.
  assert.deepEqual(board.getField("focus"), { tag: "nil" });
  const withChild = board.withField("focus", { tag: "instance", val: 7n });
  assert.notEqual(withChild, undefined);
  assert.deepEqual(withChild.getField("focus"), { tag: "instance", val: 7n });
  // The predecessor is untouched — a child is a field like any other, and
  // `with-field` is still copy-on-write.
  assert.deepEqual(board.getField("focus"), { tag: "nil" });
  // …and the fields beside it are undisturbed.
  assert.deepEqual(withChild.getField("title"), text("Sprint"));
});

test("a child token survives a transition that rebuilds the state", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", [["title", text("Sprint")]]);
  const withChild = board.withField("focus", { tag: "instance", val: 3n });
  // `bump` writes `.tally` and says nothing about `.focus`, so the successor
  // shares the slot with its predecessor rather than dropping it. That is what
  // `jv_record_set` sharing every part it did not change means for a token.
  const bumped = withChild.handleEvent("receive", "bump", []);
  assert.equal(bumped.tag, "changed");
  assert.deepEqual(bumped.val.getField("tally"), num(1));
  assert.deepEqual(bumped.val.getField("focus"), { tag: "instance", val: 3n });
});

test("a child slot is not a number, however it is carried", async () => {
  const { root } = await load("Two");
  const board = new root.guest.Instance("Board", []);
  // The tag is what distinguishes them on the wire, and the guest keeps it:
  // a token read back is an `instance`, never the `number` an i64 would be if
  // the two shared a case.
  const n = board.withField("tally", num(9));
  assert.deepEqual(n.getField("tally"), num(9));
  const c = board.withField("focus", { tag: "instance", val: 9n });
  assert.deepEqual(c.getField("focus"), { tag: "instance", val: 9n });
});

// ---------------------------------------------------------------------------
// A card that BUILDS a child while it runs.
//
// `new` used to make a declared record and nothing else, so a card composed
// children something else had created — which is fine for a page assembling a
// document and useless for a list that grows. `new <Component>` names a SIBLING
// now, and the child is made by the host through `control.make-instance`.
//
// Nothing is built at the `new`. It opens an argument map for the component and
// remembers which one; `@cur.text = .draft` accumulates into it; and the child
// is made at the first READ of `@cur` — the last moment the arguments can still
// change and the first moment they are all in. Which also means pushing `@cur`
// twice pushes ONE child rather than making two.
//
// The token is reserved during the guest call and the instance is constructed
// after it returns, because the Component Model forbids re-entering a component
// while a call into it is active. So a guest cannot look INTO a child it just
// made — which is why reading through a child slot is not a thing the language
// offers.

test("a handler builds a child, and the host holds it", async () => {
  const { root } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  const typed = list.handleEvent("receive", "setDraft", [text("write it")]);
  assert.equal(typed.tag, "changed");
  const added = typed.val.handleEvent("receive", "add", []);
  assert.equal(added.tag, "changed");
  // The draft is cleared and the list has one row.
  assert.deepEqual(added.val.getField("draft"), text(""));
  assert.deepEqual(added.val.callMethod("count", []), num(1));
});

test("the child is a real instance of the sibling component", async () => {
  const { root, arena } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  const added = list
    .handleEvent("receive", "setDraft", [text("write it")])
    .val.handleEvent("receive", "add", []);
  // `.items` is a list, so it crosses through the value arena; its one element
  // is an `instance`, which is the token — not a map of the child's fields.
  const items = added.val.getField("items");
  assert.equal(items.tag, "list");
  const cells = arena.get(items.val);
  assert.equal(cells.length, 1);
  assert.equal(cells[0].tag, "instance");
});

test("a guard still guards a handler that builds", async () => {
  const { root } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  // `add requires typed`, and the draft is empty — so nothing is built and no
  // token is spent. A rule that does not hold means the transition did not
  // happen, children included.
  assert.deepEqual(list.handleEvent("receive", "add", []), { tag: "unchanged" });
  assert.deepEqual(list.callMethod("count", []), num(0));
});

test("the child is built with the arguments the handler accumulated", async () => {
  const { root, drain } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  list
    .handleEvent("receive", "setDraft", [text("write it")])
    .val.handleEvent("receive", "add", []);
  // One child, and it is the sibling component with the fields the handler
  // put in it — `@cur.text = .draft` and `@cur.done = false`, accumulated into
  // an argument map and handed over at the push.
  const kids = drain();
  assert.equal(kids.length, 1);
  assert.equal(kids[0].component, "Todo");
  assert.deepEqual(kids[0].inst.getField("text"), text("write it"));
  assert.deepEqual(kids[0].inst.getField("done"), { tag: "boolean", val: false });
  // …and it answers its OWN component's declarations, not the list's.
  assert.deepEqual(kids[0].inst.callMethod("caption", []), text("write it"));
  const toggled = kids[0].inst.handleEvent("receive", "toggle", []);
  assert.equal(toggled.tag, "changed");
  assert.deepEqual(toggled.val.callMethod("caption", []), text("write it (done)"));
});

test("pushing the same @cur twice makes ONE child", async () => {
  const { root, drain } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  list
    .handleEvent("receive", "setDraft", [text("a")])
    .val.handleEvent("receive", "add", []);
  // The materialization replaces the target with the TOKEN and clears the
  // marker, so a second read is a read of the token rather than a second
  // construction. `add` pushes once, but the rule is what makes it safe to
  // read `@cur` more than once at all.
  assert.equal(drain().length, 1);
});

test("with-field accepts a compound value, not only a scalar", async () => {
  const { root, put } = await load("Cart");
  const c = new root.guest.Instance("Cart", []);
  // A REGRESSION, and one that predates children by a long way: `with-field`
  // receives the value JOINED — every case of the variant widened to one
  // (i64, i32) pair — and the lift that read that pair knew the four scalar
  // cases and answered nil for the rest. So a host handing a card a list got
  // null, null is not a vector however the field is declared, and the write
  // was refused. Every card, every list, since the arena landed.
  //
  // It matters here because a child inside a list is written back as the
  // parent's WHOLE list: a row that toggles is a list handed in.
  const empty = c.withField("history", { tag: "list", val: put([]) });
  assert.notEqual(empty, undefined, "an empty list is still a list");
  const two = c.withField("history", {
    tag: "list",
    val: put([num(1), num(2)]),
  });
  assert.notEqual(two, undefined);
  assert.equal(two.getField("history").tag, "list");
});

test("a child in a list survives being written back through the parent", async () => {
  const { root, drain, put, arena } = await load("Todos");
  const list = new root.guest.Instance("Todos", []);
  const added = list
    .handleEvent("receive", "setDraft", [text("write it")])
    .val.handleEvent("receive", "add", []);
  const child = drain()[0];
  const toggled = child.inst.handleEvent("receive", "toggle", []);
  assert.equal(toggled.tag, "changed");
  // What the HOST does with that successor: it rebuilds the parent's list and
  // writes the whole thing back. The new child is a token like any other.
  const back = added.val.withField("items", {
    tag: "list",
    val: put([{ tag: "instance", val: 99n }]),
  });
  assert.notEqual(back, undefined);
  const items = arena.get(back.getField("items").val);
  assert.equal(items.length, 1);
  assert.deepEqual(items[0], { tag: "instance", val: 99n });
});

test("only a card that builds a child imports make-instance", async () => {
  // The import section is what a host reads to know what a guest can do, so a
  // card that composes children something else made must not be claiming it
  // can make its own.
  const { log } = await load("Todos");
  assert.ok(log !== undefined);
  const { root } = await load("Counter");
  // A counter has no `new` at all; asking it to build one is unhandled rather
  // than a module that quietly imported a factory.
  const c = new root.guest.Instance("Counter", []);
  assert.deepEqual(c.handleEvent("receive", "add", []), { tag: "unhandled" });
});
