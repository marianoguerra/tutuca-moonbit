// The proof.
//
// Three modules, produced three different ways, instantiated together and
// composed into one tree. Each test below is one thing the current format
// cannot do, with the reason it cannot named in the comment.
//
//   node --test tgc/test/compose.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadAll, catalog, implementing, OP, TAG } from "./host.mjs";

const world = await loadAll();
const { host, rt, built } = world;
const cat = catalog(world);

const counterOf = (count, label) =>
  cat.get("Counter").make(host.map({ count: host.int(BigInt(count)), label: host.str(label) }));
const clockOf = () => cat.get("Clock").make(null);
const dashboardOf = (...children) =>
  cat.get("Dashboard").make(host.list(children.map(host.comp)));

/** The Clock's fixed instant, and the `count` it derives from it. */
const CLOCK_SECS = 1756915200n;

test("three routes, one host: every module loads and declares itself", () => {
  assert.deepEqual(
    [...cat.keys()].sort(),
    ["Clock", "Counter", "Dashboard"],
  );
  // dashboard.body.wat — a person wrote it, the builder prepended the types.
  assert.equal(cat.get("Dashboard").module, "tgc.proto.dashboard");
  // counter.wax — a COMPILER emitted the types, from tgc/abi.
  assert.equal(cat.get("Counter").module, "tgc.proto.counter");
  // clock.whole.wat — its own preamble, its own names, nothing shared but shape.
  assert.equal(cat.get("Clock").module, "tgc.proto.clock");
});

test("a component holds another module's instance in its own state", () => {
  // Not a token, not a path, not a host-side table keyed by an integer: the
  // instance. `make-instance` in the current format is same-bundle only, and a
  // field declared as a bare `component` is held by the HOST instead.
  const dash = dashboardOf(counterOf(3, "Left"), clockOf());
  const slots = host.get(dash, "slots");
  assert.equal(slots.length, 2);
  assert.ok(slots.every((s) => s.inst));
});

test("a parent reads a field THROUGH a child", () => {
  // "a guest holds bridge handles, not pointers, so a parent cannot inspect its
  // own children" — dyncomp/DESIGN.md. Here it is one `call_ref`.
  const dash = dashboardOf(counterOf(3, "Left"), clockOf());
  assert.deepEqual(host.get(dash, "labels"), ["Left", "Clock"]);
  assert.equal(host.get(dash, "total"), 3n + CLOCK_SECS);
});

test("a transition returns a successor and shares what it did not change", () => {
  const before = dashboardOf(counterOf(3, "Left"), clockOf());
  const after = host.successor(host.call(before, OP.HANDLE_MESSAGE, "bumpAll"));
  assert.ok(after);
  // Both children advanced by one, and the parent is a new instance.
  assert.equal(host.get(after, "total"), 3n + 1n + CLOCK_SECS + 1n);
  assert.notEqual(host.id(after), host.id(before));
  // Copy on write: the predecessor is untouched, which is the model the
  // language already has rather than an imitation of it.
  assert.equal(host.get(before, "total"), 3n + CLOCK_SECS);
});

test("two modules hold each other, and neither made the other", () => {
  const counter = counterOf(7, "Left");
  const clock = clockOf();
  const counter2 = host.successor(
    host.call(counter, OP.WITH_FIELD, "peer", [], host.comp(clock)),
  );
  const clock2 = host.successor(
    host.call(clock, OP.WITH_FIELD, "peer", [], host.comp(counter2)),
  );
  // Each reads a field of the other by calling it.
  assert.equal(host.get(counter2, "peerLabel"), "Clock");
  assert.equal(host.get(clock2, "peerCount"), 7n);
});

test("a module is re-entered while a call into it is active", () => {
  // The Component Model forbids exactly this, which is why a compiled card
  // "cannot look INTO a child it just made". Core wasm has no such rule.
  //
  // The stack that runs here is:
  //   Dashboard.get("peerLabels")
  //     -> Counter.get("peerLabel")        [a different module]
  //          -> Dashboard.get("label")     [back into the first, still on the stack]
  const counter = counterOf(1, "Left");
  const dash = dashboardOf(counter);
  const counterWithPeer = host.successor(
    host.call(counter, OP.WITH_FIELD, "peer", [], host.comp(dash)),
  );
  const cycle = dashboardOf(counterWithPeer);
  assert.deepEqual(host.get(cycle, "peerLabels"), ["Dashboard"]);
});

test("bytes and an instant survive crossing two module boundaries", () => {
  // The old value type had neither arm, and compounds crossed as u64 handles
  // into a host arena valid only for the duration of one call. Here a value is
  // a reference: it is handed over, not flattened.
  const clock = clockOf();
  const dash = dashboardOf(counterOf(0, "Left"), clock);
  const viaParent = host.get(dash, "slots")[1].inst;
  assert.deepEqual(host.get(viaParent, "blob"), new Uint8Array([0, 255, 254, 1]));
  assert.deepEqual(host.get(viaParent, "at"), { secs: CLOCK_SECS, nanos: 123456789 });
});

test("an integer past 2^53 is still itself", () => {
  // "a 64-bit id is a `str`" — the current WIT, conceding the cost of having
  // one number. This one has two.
  const big = 9007199254740993n;
  const counter = counterOf(big, "Big");
  assert.equal(host.get(counter, "count"), big);
});

test("a slot is filled by PROTOCOL, not by name", () => {
  // What replaces a flat `by_name` whose last registration silently wins, and a
  // registry that breaks a tie by "most recently loaded".
  const tiles = implementing(cat, "tut.demo.tile@1").map((c) => c.file).sort();
  assert.deepEqual(tiles, ["clock", "counter"]);
  // And it can be asked of the INSTANCE, with no catalog in the path at all.
  assert.equal(host.implementsId(counterOf(0, "x"), "tut.demo.tile@1"), true);
  assert.equal(host.implementsId(clockOf(), "tut.demo.tile@1"), true);
  assert.equal(host.implementsId(dashboardOf(), "tut.demo.tile@1"), false);
});

test("a module cannot read another module's state", () => {
  // `state` is `&?eq` and each module casts it back to a type only it can name.
  // Opacity is the engine's, not a convention's and not a handle table's.
  const counter = counterOf(1, "Left");
  const clock = clockOf();
  // The Counter's own vtable on the Counter's own state: fine.
  assert.equal(
    host.toJs(rt.cross_get(counter, counter, host.bytes("count"))),
    1n,
  );
  // The Counter's vtable pointed at the Clock's state: a trap, not a wrong
  // answer and not a silent null.
  assert.throws(
    () => rt.cross_get(counter, clock, host.bytes("count")),
    (e) => e instanceof WebAssembly.RuntimeError,
  );
});

test("an unknown op answers 'I do not do that' rather than failing", () => {
  // How the op space stays extensible: an op invented after a module was built
  // gets the same answer as one the module simply does not implement.
  const counter = counterOf(1, "Left");
  assert.equal(host.call(counter, 12345, "whatever"), null);
  assert.equal(host.call(counter, OP.PERSIST, "whatever"), null);
});

test("a module's import section is its whole authority", () => {
  // No memory, no table, no WASI. What a module can reach is a list a host can
  // read before running a line of it.
  for (const name of ["dashboard", "counter", "clock"]) {
    const wat = execFileSync("wasm-tools", ["print", built[name]], { encoding: "utf8" });
    const imports = [...wat.matchAll(/\(import "([^"]+)" "([^"]+)"/g)].map((m) => m[1]);
    assert.ok(imports.length > 0, `${name} imports nothing at all?`);
    assert.deepEqual([...new Set(imports)], ["tut"], `${name} reaches past tut`);
    assert.ok(!/\(memory /.test(wat), `${name} declares a memory`);
    assert.ok(!/\(table /.test(wat), `${name} declares a table`);
  }
});

test("a perturbed rec group is refused at link, not at a cast three calls later", () => {
  // The freeze rule, made real by the engine. One extra type INSIDE the group
  // and every type in it becomes a different type.
  const src = readFileSync(join(process.cwd(), "tgc/proto/clock.whole.wat"), "utf8");
  const perturbed = src.replace(
    "  (rec\n",
    "  (rec\n    (type $V_later (sub final (struct (field $extra i32))))\n",
  );
  assert.notEqual(perturbed, src, "the perturbation did not apply");
  const path = join(process.cwd(), "_build/tgc/clock-perturbed.wat");
  writeFileSync(path, perturbed);
  const wasmPath = path.replace(/\.wat$/, ".wasm");
  // It is a perfectly valid module on its own. That is the point: nothing about
  // it is wrong until it is asked to share types with somebody.
  execFileSync("wasm-tools", ["parse", path, "-o", wasmPath]);
  execFileSync("wasm-tools", ["validate", wasmPath]);
  assert.rejects(
    () => WebAssembly.instantiate(readFileSync(wasmPath), { tut: world.tut }),
    (e) => e instanceof WebAssembly.LinkError || /does not match/.test(e.message),
  );
});

test("every value the host reads has a tag the ABI defines", () => {
  const dash = dashboardOf(counterOf(1, "Left"), clockOf());
  const seen = new Set();
  const walk = (v) => {
    if (v === null) return;
    seen.add(rt.kind_of(v));
  };
  walk(host.getRaw(dash, "total"));
  walk(host.getRaw(dash, "slots"));
  walk(host.getRaw(dash, "labels"));
  const clock = host.get(dash, "slots")[1].inst;
  walk(host.getRaw(clock, "at"));
  walk(host.getRaw(clock, "blob"));
  assert.deepEqual(
    [...seen].sort((a, b) => a - b),
    [TAG.INT, TAG.BIN, TAG.INSTANT, TAG.LIST].sort((a, b) => a - b),
  );
});
