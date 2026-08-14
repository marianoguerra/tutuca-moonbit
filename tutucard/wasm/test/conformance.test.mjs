// The wasm backend, run against the conformance corpus.
//
// `tscript/conformance/corpus.mbt` is the language's semantics as data, and
// `tscript/conformance/mbt/` is one backend held to it. This is the
// other one: each case becomes a card, the card is compiled, and the module is
// driven through `dyncomp/host/wasm/abi.mjs` — the same host a downloaded
// bundle gets. A case the interpreter passes and this does not is a bug in one
// of them rather than a difference of opinion.
//
// The table crosses as JSON because a compiled card can only be run from node;
// `cmd/corpus` writes it, and checks itself against the corpus on the way out.
//
// A case whose handler the generator REFUSES is skipped and counted rather
// than failed, and the count is now asserted to be ZERO. It was the honest
// measure of what this backend did not do yet, and what it measured was
// `request`; with that compiled there is nothing in the corpus this backend
// turns away, so the assertion says so instead of watching a number.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { instantiate } from "../../../dyncomp/host/wasm/abi.mjs";

// The module root: `tutucard/wasm/test` -> up three.
const MODULE = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const out = mkdtempSync(join(tmpdir(), "cardwasm-corpus-"));
const CLI = join(MODULE, "_build/native/debug/build/cmd/cardwasm/cardwasm.exe");

execFileSync("moon", ["build", "--target", "native", "cmd/cardwasm", "cmd/card-corpus"], {
  cwd: MODULE,
  stdio: "inherit",
});
execFileSync("moon", ["run", "--target", "native", "cmd/card-corpus", "--", join(out, "corpus.json")], {
  cwd: MODULE,
  stdio: "pipe",
});
const DUMP = JSON.parse(readFileSync(join(out, "corpus.json"), "utf8"));
const CORPUS = DUMP.cases;
// The other half of the table: what a block SAID, rather than what the state
// became. This backend was never held to it, which is where its
// `enrich` / `enrichScope` gap lived — both were absent from the generator
// entirely, with no refusal to show for it.
const VALUE_CORPUS = DUMP.valueCases;

// The declaration kind each bucket dispatches, which is the word a refusal is
// reported under.
const KIND = { input: "on", receive: "receive", bubble: "bubble", response: "response" };

/**
 * A corpus case as a card. The corpus carries the two script blocks; a card
 * also wants a template, and an empty one is enough — nothing here renders.
 */
function cardOf(c) {
  return (
    `<script type="tutuca/state">\n${c.schema}\n</` + `script>\n` +
    `<script type="tutuca/script">\n${c.script}\n</` + `script>\n` +
    `<template id="${c.component}"><div></div></template>\n`
  );
}

/** A corpus value (plain JSON) as a `values.value`, interning compounds. */
function toWire(v, put) {
  if (v === null) return { tag: "nil" };
  if (typeof v === "boolean") return { tag: "boolean", val: v };
  if (typeof v === "number") return { tag: "number", val: v };
  if (typeof v === "string") return { tag: "text", val: v };
  if (Array.isArray(v)) return { tag: "list", val: put(v.map((x) => toWire(x, put))) };
  const m = new Map();
  for (const [k, x] of Object.entries(v)) m.set(k, toWire(x, put));
  return { tag: "map", val: put(m) };
}

/** The reverse, resolving handles through the arena the host owns. */
function fromWire(v, arena) {
  if (v === undefined) return undefined;
  switch (v.tag) {
    case "nil": return null;
    case "boolean": return v.val;
    case "number": return v.val;
    case "text": return v.val;
    case "list": return arena.get(v.val).map((x) => fromWire(x, arena));
    case "map": {
      const o = {};
      for (const [k, x] of arena.get(v.val)) o[k] = fromWire(x, arena);
      return o;
    }
    default: return { unknown: v.tag };
  }
}

/** Compile one case and instantiate it. Answers null when it did not compile. */
async function build(c, i, source) {
  const stem = `case${i}`;
  writeFileSync(join(out, `${stem}.html`), source ?? cardOf(c));
  let log;
  try {
    log = execFileSync(CLI, [join(out, `${stem}.html`), out], { encoding: "utf8" });
  } catch (e) {
    return { error: (e.stdout ?? "") + (e.stderr ?? "") };
  }
  // A whole-card failure — a `GenError` rather than a per-declaration refusal —
  // is reported and then exits 0, so the absence of the output is the signal.
  if (!existsSync(join(out, `${stem}.descriptor.json`))) {
    return { error: log.trim() };
  }
  const descriptor = JSON.parse(readFileSync(join(out, `${stem}.descriptor.json`), "utf8"));
  const wasm = readFileSync(join(out, `${stem}.wasm`));
  const arena = new Map();
  let next = 1n;
  const put = (value) => {
    const handle = next++;
    arena.set(handle, value);
    return handle;
  };
  const effects = [];
  const root = await instantiate(
    () => WebAssembly.compile(wasm),
    {
      "tutuca:component/values": {
        listLen: (h) => arena.get(h).length,
        listGet: (h, j) => arena.get(h)[j],
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
        // Bound but NOT collected: a declined rule says so on this channel, and
        // what the corpus asserts is the successor and the effects. The
        // interpreter's adapter quiets its `warn_hook` for the same reason.
        log: () => {},
        emit: (name, args) => effects.push({ kind: "bubble", name, args }),
        send: (name, args) => effects.push({ kind: "send", name, args }),
        stopPropagation: () => effects.push({ kind: "stop", name: "", args: [] }),
        // The `opts` a compiled card sends is always `RequestOpts::new()`, which
        // is what the interpreter hands `ctx.request` too — so the corpus, which
        // records a request as a name and its arguments, has nothing to say
        // about it and neither does this.
        request: (name, args, _opts) => effects.push({ kind: "request", name, args }),
      },
    },
    { ...descriptor, core: `${stem}.wasm` },
  );
  return { root, arena, put, effects, log };
}

const results = { passed: [], refused: [], rejected: [], failed: [] };

test("the wasm backend agrees with the conformance corpus", async () => {
  for (const [i, c] of CORPUS.entries()) {
    const b = await build(c, i);
    if (b.error) {
      // A card the CHECKER turns away is not a gap in this backend: it does
      // not typecheck, which is true of every backend and would be true of a
      // hand-written module. The corpus has one such row — a name that
      // resolves to nothing — and the interpreter abandons the transition at
      // run time where this says so when the card is compiled.
      if (b.error.startsWith("rejected:")) {
        results.rejected.push(`${c.name}: ${b.error.slice("rejected:".length).trim()}`);
      } else {
        results.failed.push(`${c.name}: did not compile — ${b.error.trim()}`);
      }
      continue;
    }
    const { root, arena, put, effects, log } = b;

    // Refused by name, with the reason, in the CLI's log. A refused handler is
    // absent from the module, so the host hears `unhandled` and falls back —
    // which is a real answer, just not one this corpus row is about.
    if (log.includes(`refused ${KIND[c.bucket]} ${c.handler}`)) {
      results.refused.push(c.name);
      continue;
    }

    const ctorArgs = Object.entries(c.before).map(([k, v]) => [k, toWire(v, put)]);
    let inst;
    try {
      inst = new root.guest.Instance(c.component, ctorArgs);
    } catch (e) {
      results.failed.push(`${c.name}: the constructor threw — ${e.message}`);
      continue;
    }

    let res;
    try {
      res = inst.handleEvent(c.bucket, c.handler, c.args.map((a) => toWire(a, put)));
    } catch (e) {
      results.failed.push(`${c.name}: the dispatch threw — ${e.message}`);
      continue;
    }

    // What a host observes: the state it renders next. `after: null` means the
    // transition did not happen, and the state it renders is the one it had.
    const wantState = c.after ?? c.before;
    const after = res.tag === "changed" ? res.val : inst;
    const got = {};
    for (const k of Object.keys(wantState)) {
      got[k] = fromWire(after.getField(k), arena);
    }

    const problems = [];
    try {
      assert.deepEqual(got, wantState);
    } catch {
      problems.push(
        `state is ${JSON.stringify(got)}, want ${JSON.stringify(wantState)}`,
      );
    }
    const gotEffects = effects.map((e) => ({
      kind: e.kind,
      name: e.name,
      args: e.args.map((a) => fromWire(a, arena)),
    }));
    try {
      assert.deepEqual(gotEffects, c.effects);
    } catch {
      problems.push(
        `effects are ${JSON.stringify(gotEffects)}, want ${JSON.stringify(c.effects)}`,
      );
    }
    if (problems.length) results.failed.push(`${c.name}: ${problems.join("; ")}`);
    else results.passed.push(c.name);
  }

  console.log(
    `corpus: ${results.passed.length} passed, ` +
      `${results.rejected.length} rejected as invalid, ` +
      `${results.refused.length} refused, ${results.failed.length} failed ` +
      `(of ${CORPUS.length})`,
  );
  if (results.rejected.length) {
    console.log("rejected (the card does not check):\n  " + results.rejected.join("\n  "));
  }
  if (results.refused.length) {
    console.log("refused:\n  " + results.refused.join("\n  "));
  }
  if (results.failed.length) {
    console.log("failed:\n  " + results.failed.join("\n  "));
  }
  assert.deepEqual(results.failed, []);
  // And nothing in the corpus is refused any more. This used to be a COUNT
  // that was only allowed to shrink, because `request` sat here and there was
  // no date on when it would not. It does not sit here now, so the honest
  // assertion is the empty one: a refusal reaching this table again is a
  // feature the language has and this backend has stopped having.
  assert.deepEqual(results.refused, []);
});

// ---------------------------------------------------------------------------

test("the wasm backend agrees with the corpus about value bodies", async () => {
  const failures = [];
  let ran = 0;
  for (const [i, c] of VALUE_CORPUS.entries()) {
    // The declaration is reached through `call-method` in every role, so the
    // card is built the same way and only the ARGUMENTS differ. The kind word
    // a refusal is reported under differs too: a `@when` is a `pred`, and an
    // enricher is its own word.
    const b = await build(c, 1000 + i);
    if (b.error) {
      failures.push(`${c.name}: did not compile — ${b.error.trim()}`);
      continue;
    }
    const { root, arena, put, log } = b;
    if (/\brefused (pred|compute|invariant|enrich|enrichScope) /.test(log)) {
      failures.push(`${c.name}: refused — ${log.trim()}`);
      continue;
    }
    const ctorArgs = Object.entries(c.state).map(([k, v]) => [k, toWire(v, put)]);
    let inst;
    try {
      inst = new root.guest.Instance(c.component, ctorArgs);
    } catch (e) {
      failures.push(`${c.name}: the constructor threw — ${e.message}`);
      continue;
    }

    // What each role is HANDED, which `component/instance.mbt` decides and
    // `dyncomp/host/dynobj.mbt` passes on. A method gets its own arguments; a
    // filter gets the row; an enricher gets the bindings first and then the
    // row; the scope form gets nothing at all.
    const row = [toWire(c.key, put), toWire(c.value, put), { tag: "nil" }];
    const args = {
      method: () => c.args.map((a) => toWire(a, put)),
      when: () => row,
      enrich: () => [{ tag: "map", val: put(new Map()) }, ...row],
      enrichScope: () => [],
    }[c.role]();

    let out;
    try {
      out = inst.callMethod(c.callable, args);
    } catch (e) {
      failures.push(`${c.name}: the call threw — ${e.message}`);
      continue;
    }
    ran += 1;

    const got = fromWire(out, arena);
    const want = c.answer;
    // `ANothing` is a body that could not finish. Across this boundary that is
    // nil, which is the same thing `call_method_fn` answers for a `tc_fail`.
    if (want.kind === "nothing") {
      if (got !== null) failures.push(`${c.name}: answered ${JSON.stringify(got)}, want nothing`);
      continue;
    }
    if (want.kind === "bool") {
      // A `@when` is read for its TRUTHINESS, not for being a boolean: the
      // corpus has `pred named { .name }` answering a string, and the renderer
      // asks whether the row survives.
      const truthy = got !== null && got !== false && got !== 0 && got !== "";
      if (truthy !== want.value) {
        failures.push(`${c.name}: answered ${JSON.stringify(got)}, want ${want.value}`);
      }
      continue;
    }
    if (want.kind === "binds") {
      // Only what the body WROTE. The compiled enricher answers the incoming
      // bindings plus its own, and the incoming ones are empty here — the
      // loop's `key` and `value` are the renderer's and never go in the map.
      try {
        assert.deepEqual(got, want.value);
      } catch {
        failures.push(
          `${c.name}: answered ${JSON.stringify(got)}, want ${JSON.stringify(want.value)}`,
        );
      }
      continue;
    }
    try {
      assert.deepEqual(got, want.value);
    } catch {
      failures.push(
        `${c.name}: answered ${JSON.stringify(got)}, want ${JSON.stringify(want.value)}`,
      );
    }
  }
  console.log(
    `value corpus: ${ran - failures.length} passed, ${failures.length} failed ` +
      `(of ${VALUE_CORPUS.length})`,
  );
  if (failures.length) console.log("failed:\n  " + failures.join("\n  "));
  assert.deepEqual(failures, []);
});

// ---------------------------------------------------------------------------

test("a map field keeps its contents AND its insertion order", async () => {
  // This used to assert the opposite, and the comment where the assertion is
  // said to flip it when the stdlib grew an ordered map. It did
  // (`jv_ordered_map_*`), so it is flipped.
  //
  // Why it matters: tutuca's `Value::Map` is MoonBit's `Map`, which is
  // insertion ordered — re-assigning a key keeps its place, removing drops it,
  // re-adding appends. `statedef`'s `TOMap` is `Map[String, T]` and is
  // described as an ordered map, and the renderer's `@each` indexes a `Map`
  // directly (`core/value_dyn.mbt`), so a view looping over a map field
  // renders in that order. A HAMT would have rendered it in trie order.
  const ORDER = ["zebra", "apple", "mango", "kiwi", "banana", "cherry"];
  const b = await build(
    null,
    "maporder",
    `<script type="tutuca/state">\n  state M { m: Map[String, Int] }\n</` +
      `script>\n<script type="tutuca/script">\n  on put(k, v) { .m.setAt k v }\n  on drop(k) { .m.deleteAt k }\n</` +
      `script>\n<template id="M"><div></div></template>\n`,
  );
  assert.equal(b.error, undefined);
  const { root, arena } = b;

  const put = (c, k, v) => {
    const r = c.handleEvent("input", "put", [
      { tag: "text", val: k },
      { tag: "number", val: v },
    ]);
    return r.tag === "changed" ? r.val : c;
  };
  const keys = (c) => [...arena.get(c.getField("m").val).keys()];

  let c = new root.guest.Instance("M", []);
  for (const [i, k] of ORDER.entries()) c = put(c, k, i);
  assert.deepEqual(keys(c), ORDER);

  // Re-assigning an existing key keeps its place.
  assert.deepEqual(keys(put(c, "mango", 99)), ORDER);

  // Removing drops it, and re-adding appends at the end.
  let d = c.handleEvent("input", "drop", [{ tag: "text", val: "mango" }]).val;
  assert.deepEqual(keys(d), ORDER.filter((k) => k !== "mango"));
  assert.deepEqual(keys(put(d, "mango", 1)), [
    ...ORDER.filter((k) => k !== "mango"),
    "mango",
  ]);
});
