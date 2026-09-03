// The language's semantics, run.
//
// `tscript/conformance` is the corpus: a schema, a script, a state, a dispatch,
// and what the state and the effects are afterwards. `cmd/tgc-corpus` compiles
// each row to a `tgc` module and writes the row beside it; this drives them.
//
// A backend not driven by the corpus is a backend with its own semantics. This
// one is the third over `tscript`'s one AST, so being held to the same table as
// the other two is the whole point of it existing.
//
//   moon run --target native cmd/tgc-corpus -- _build/tgc/corpus
//   node --test tgc/test/conformance.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadAll, OP } from "./host.mjs";

const dir = join(process.cwd(), "_build/tgc/corpus");
mkdirSync(dir, { recursive: true });
execFileSync("moon", ["run", "--target", "native", "cmd/tgc-corpus", "--", dir], {
  cwd: process.cwd(),
  encoding: "utf8",
});
const rows = JSON.parse(readFileSync(join(dir, "cases.json"), "utf8"));

// One runtime for every case: `tut` is shared, which is the point of it.
const world = await loadAll();
const { rt, host } = world;

/**
 * The effect recorder.
 *
 * Effects are `tut` imports and the HOST buffers them, because the host is what
 * brackets the call and therefore knows when it ended. A transition that
 * abandons discards what it buffered — an effect performed before a statement
 * that fails never happened.
 */
let buffered = [];
const ROUTES = { 1: "dyn", 2: "lex", 3: "dyn lex", 4: "lex dyn" };
const argsOf = (a) => {
  const out = [];
  for (let i = 0; i < rt.list_len(rt.mk_list(a)); i++) out.push(host.toJs(rt.list_at(rt.mk_list(a), i)));
  return out;
};
const effects = {
  eff_send: (name, args) =>
    buffered.push({ kind: "send", name: host.text(name), args: argsOf(args), route: "" }),
  // Two runtime calls, one word in the language: the corpus records both as
  // `reply`, and the arguments say which it was — exactly as the source does.
  eff_reply: (name, args) =>
    buffered.push({ kind: "reply", name: host.text(name), args: argsOf(args), route: "" }),
  eff_answer: (v) =>
    buffered.push({ kind: "reply", name: "", args: [host.toJson(v)], route: "" }),
  eff_ask: (name, args, route) =>
    buffered.push({ kind: "ask", name: host.text(name), args: argsOf(args), route: ROUTES[route] }),
  eff_notify: (name, args, route) =>
    buffered.push({ kind: "notify", name: host.text(name), args: argsOf(args), route: ROUTES[route] }),
  eff_forward: (args, route) =>
    buffered.push({ kind: "forward", name: "", args: argsOf(args), route: ROUTES[route] }),
  eff_fail: (v) => buffered.push({ kind: "fail", name: "", args: [host.toJs(v)], route: "" }),
  eff_drop: () => buffered.push({ kind: "drop", name: "", args: [], route: "" }),
  // What a declined rule said. The corpus does not assert on it — a rule that
  // does not hold is recorded as the transition NOT HAPPENING — so it is
  // collected rather than compared.
  eff_log: (msg) => logged.push(host.text(msg)),
};

let logged = [];

/** A row's JSON values, built into the module's own value world. */
const build = (j) => host.ofJson(j);

for (const row of rows) {
  test(`${row.status}: ${row.name}`, async () => {
    if (row.status === "rejected") {
      // A case the corpus states as invalid. It is rejected WHOLE rather than
      // refused per declaration, and that distinction is the assertion.
      assert.match(row.why, /does not check/);
      return;
    }
    assert.deepEqual(row.refusals, [], "a corpus case was refused");

    const wasm = readFileSync(join(dir, row.module));
    const { instance } = await WebAssembly.instantiate(wasm, {
      tut: { ...world.tut, ...effects },
    });
    const ex = instance.exports;

    const inst = ex["tgc.make"](host.bytes(row.component), build(row.before));
    assert.ok(inst, `${row.component} would not construct`);

    buffered = [];
    const op = row.bucket === "receive" ? OP.HANDLE_MESSAGE : OP.HANDLE_INTENT;
    const answer = host.call(inst, op, row.handler, (row.args ?? []).map(build));

    if (row.after === null) {
      // "The transition did not happen" is a real answer, and one a backend can
      // get wrong in a way nothing else would notice.
      assert.equal(answer, null, "expected no successor");
      return;
    }
    assert.notEqual(answer, null, "expected a successor");
    const next = host.successor(answer);
    for (const [field, want] of Object.entries(row.after)) {
      assert.deepEqual(
        host.toJson(host.getRaw(next, field)),
        want,
        `field ${field}`,
      );
    }
    assert.deepEqual(buffered, row.effects, "effects");
  });
}

test("the corpus is not empty", () => {
  assert.ok(rows.length >= 20, `${rows.length} rows`);
});

// ── the OTHER table ─────────────────────────────────────────────────────────
//
// Seventeen rows about what a block SAID rather than what the state became.
// `tutucard/wasm`'s worst gap lived here and was INVISIBLE: `enrich` and
// `bindWith` appeared nowhere in its generator, so a card using them compiled
// with no refusal to show for it and quietly lost its bindings. No transition
// case was asking.

const valueRows = JSON.parse(readFileSync(join(dir, "value_cases.json"), "utf8"));
const VALUE_OP = {
  method: OP.COMPUTE,
  when: OP.WHEN,
  enrich: OP.ENRICH,
  bindWith: OP.ENRICH_SCOPE,
};

for (const row of valueRows) {
  test(`${row.role}: ${row.name}`, async () => {
    assert.equal(row.status, "compiled", row.why ?? "");
    assert.deepEqual(row.refusals, [], "a value case was refused");

    const wasm = readFileSync(join(dir, row.module));
    const { instance } = await WebAssembly.instantiate(wasm, {
      tut: { ...world.tut, ...effects },
    });
    const inst = instance.exports["tgc.make"](
      host.bytes(row.component),
      build(row.state),
    );
    assert.ok(inst, `${row.component} would not construct`);

    // The render row arrives POSITIONALLY, at offsets that differ by shape:
    // a `pred` is handed (key, value, iter) and an `enrich` is handed the
    // binding map first. A compiled declaration runs after the render stack
    // rather than inside it, so there is nothing for it to look up.
    const row3 = [build(row.key), build(row.value), rt.mk_null()];
    const args = {
      method: () => (row.args ?? []).map(build),
      when: () => row3,
      enrich: () => [rt.mk_map(rt.entries_new(0)), ...row3],
      bindWith: () => [],
    }[row.role]();

    const answer = host.call(inst, VALUE_OP[row.role], row.callable, args);

    if (row.answer.kind === "nothing") {
      // "There is no answer" is a real answer, and the one a runtime is most
      // tempted to replace with something plausible: `len true` is not zero and
      // `min` of a string and a number is not the string.
      assert.equal(answer, null, "expected no answer");
      return;
    }
    assert.notEqual(answer, null, "expected an answer");
    if (row.answer.kind === "bool") {
      assert.equal(rt.as_bool(answer) !== 0, row.answer.v);
      return;
    }
    assert.deepEqual(host.toJson(answer), row.answer.v);
  });
}
