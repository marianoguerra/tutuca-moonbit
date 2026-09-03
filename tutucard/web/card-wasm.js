// The page's half of the guest boundary, and the packer.
//
// `abi.mjs` — the same file `dyncomp` ships, copied here unchanged by
// `build/assemble.mjs` — turns a core module into an object with an
// `Instance` class. This wraps that in the four calls the MoonBit `&Guest`
// impl makes over `globalThis.__cardguest[key]`, keyed by an integer handle,
// because a MoonBit extern cannot hold a JS object.
//
// It is the js-target twin of `createTcompImports` in
// `dyncomp/host/wasm/loader.mjs`, minus everything a compiled card cannot do:
// no pending-children protocol (a card has no `make-instance`) and no clock to
// freeze (a card asks for no capability). It DOES keep a table, keyed by mount
// point — a page with two `<mb-card>` embeds has two modules, and that stopped
// being hypothetical when mounting a card became compiling one.

import { instantiate } from "./abi.mjs";

// Compound guest values travel as u64 handles into a host-side arena. A card
// can neither read nor build one — the generator emits no `values` import at
// all, so `instantiate` never binds this interface — but a host may still
// hand a list into a fixed handler operation, and it has to come back out the same shape.
function makeArena() {
  const cells = new Map();
  let next = 1n;
  const put = (v) => {
    const h = next++;
    cells.set(h, v);
    return h;
  };
  return {
    cells,
    put,
    clear: () => cells.clear(),
    api: {
      listLen: (h) => cells.get(h)?.length ?? 0,
      listGet: (h, i) => cells.get(h)?.[i] ?? { tag: "nil" },
      mapLen: (h) => cells.get(h)?.size ?? 0,
      mapKeys: (h) => [...(cells.get(h)?.keys() ?? [])],
      mapGet: (h, k) => cells.get(h)?.get(k),
      listNew: () => put([]),
      listPush: (h, v) => cells.get(h)?.push(v),
      mapNew: () => put(new Map()),
      mapSet: (h, k, v) => cells.get(h)?.set(k, v),
      toJson: (v) => JSON.stringify(guestToJson(v, cells)),
      fromJson: (s) => jsonToGuest(JSON.parse(s), put),
    },
  };
}

/** A guest `value` as the plain JSON `@tutuca.Value::to_json` speaks. */
function guestToJson(v, cells, table) {
  if (v === undefined) return null;
  switch (v.tag) {
    case "nil":
      return null;
    case "boolean":
    case "number":
    case "text":
      return v.val;
    case "list":
      return (cells.get(v.val) ?? []).map((x) => guestToJson(x, cells, table));
    case "map": {
      const out = {};
      for (const [k, x] of cells.get(v.val) ?? new Map())
        out[k] = guestToJson(x, cells, table);
      return out;
    }
    // A same-bundle CHILD, as the token the host handed the guest. It crosses
    // to the MoonBit side as the marker `dyncomp/host/wasm/loader.mjs` uses,
    // and `cardguest.mbt` turns that back into a `DynObj` through the bundle —
    // which is the only thing that knows how to wrap a handle as a component.
    //
    // The component NAME travels with it because the marker needs one: a
    // handle says which instance, not which kind, and the host has to know
    // what it is wrapping.
    case "instance": {
      const h = Number(v.val);
      const entry = table?.get(h);
      return entry ? { $dyn: { handle: h, comp: entry.comp } } : null;
    }
    default:
      return null;
  }
}

/** The other direction. */
function jsonToGuest(j, put) {
  if (j === null || j === undefined) return { tag: "nil" };
  if (typeof j === "boolean") return { tag: "boolean", val: j };
  if (typeof j === "number") return { tag: "number", val: j };
  if (typeof j === "string") return { tag: "text", val: j };
  if (Array.isArray(j)) return { tag: "list", val: put(j.map((x) => jsonToGuest(x, put))) };
  // The marker back into a token. Same spelling as `loader.mjs`, so a guest
  // reads one shape whichever host it is running under.
  if (j.$dyn && typeof j.$dyn.handle === "number") {
    return { tag: "instance", val: BigInt(j.$dyn.handle) };
  }
  const m = new Map();
  for (const [k, v] of Object.entries(j)) m.set(k, jsonToGuest(v, put));
  return { tag: "map", val: put(m) };
}

/**
 * Instantiate a compiled card and install it as `globalThis.__cardguest`.
 *
 * `module` is the compiled module to instantiate, for a caller that already has
 * one. Everything else here is per-key already — the arena, the instance table,
 * `__cardguest[key]` — so N instances off ONE module is what the shape already
 * supports; what it was missing was a way to say so. The examples pane makes one
 * instance per fixture of the same card, and compiling the same bytes once per
 * fixture on a keystroke debounce is the whole cost of that pane.
 */
export async function loadGuest(bytes, descriptor, key = "default", { module } = {}) {
  const arena = makeArena();
  let control = [];
  // The host's answers to this component's declared lookups, valid for the
  // duration of one dispatch. Empty outside one, and empty for a component
  // that declares no lookup — which is most of them.
  let bindings = {};
  // What the card SAID. `control.log` is the one call on the control interface
  // no capability gates, and for a compiled card it carries the thing an author
  // is most likely to get wrong and least able to see: a `requires`, an
  // `ensures` or an `invariant` that did not hold, with its own `format`
  // sentence evaluated over the state that was rejected.
  //
  // It used to go to the console and nowhere else, which is fine for a page a
  // person is looking at and useless to anything driving the card headlessly —
  // a declined guard and a click that missed look identical from the DOM, and
  // this is the only thing that tells them apart. So it is kept as well as
  // printed, and `takeLog()` hands it to whoever is watching.
  const logLines = [];
  // The same spelling `dyncomp/host/wasm/loader.mjs` uses, so `glue.mbt`'s
  // `path_step` and `cardguest.mbt`'s read one shape and not two.
  // WIT `intent-opts`, as the bridge's JSON — the same shape and the same
  // spelling `loader.mjs` uses, so `cardguest.mbt` and `glue.mbt` read one
  // thing. `route` lifts to the `leg` enum's own case names.
  const optsToJson = (o) => ({
    route: (o?.route ?? []).map((leg) => (typeof leg === "string" ? leg : leg?.tag)),
    onOk: o?.onOk ?? null,
    onError: o?.onError ?? null,
    onUnhandled: o?.onUnhandled ?? null,
    livePath: !!o?.livePath,
  });
  // `{inst, comp}` rather than the instance alone, because a CHILD token has to
  // come back out as a marker naming its component — a handle says which
  // instance, not which kind. A successor keeps its predecessor's component:
  // `with-field` and a `changed` dispatch both answer the same kind of thing
  // they were handed.
  //
  // Declared HERE rather than after `instantiate`, because the control imports
  // below close over it: `makeInstance` reserves a handle in this table.
  const table = new Map();
  let nextHandle = 1;
  const register = (inst, comp) => {
    const h = nextHandle++;
    table.set(h, { inst, comp });
    return h;
  };
  const instOf = (handle) => table.get(handle)?.inst;
  const compOf = (handle) => table.get(handle)?.comp ?? "";

  // Children whose token has been handed out and whose instance does not exist
  // yet. See `makeInstance`.
  const pendingChildren = [];
  const drainChildren = () => {
    while (pendingChildren.length) {
      const { handle, component, args } = pendingChildren.shift();
      const entry = table.get(handle);
      // A token dropped before it was drained is a child nobody kept; building
      // it now would be building something with no one to hold it.
      if (entry) entry.inst = new root.guest.Instance(component, args);
    }
  };

  const stepToJson = (s) =>
    s.tag === "field"
      ? { field: s.val }
      : s.tag === "item"
        ? { item: [s.val.field, s.val.key] }
        : { at: [s.val.field, Number(s.val.index)] };
  const root = await instantiate(
    () => module ?? WebAssembly.compile(bytes),
    {
      "tutuca:component/values": arena.api,
      "tutuca:component/control": {
        log: (level, msg) => {
          logLines.push(`${level}: ${msg}`);
          console.log(`[card ${level}]`, msg);
        },
        send: (name, args) =>
          control.push({ kind: "send", name, args: args.map((a) => guestToJson(a, arena.cells)) }),
        stopPropagation: () => control.push({ kind: "stopPropagation" }),
        // A reply names itself, so it carries a name the way a `send` does.
        sendReply: (name, args) =>
          control.push({
            kind: "sendReply",
            name,
            args: args.map((a) => guestToJson(a, arena.cells)),
          }),
        // The one import that ANSWERS. `bindings` was resolved by the host
        // before this call, so a name it does not carry is one the manifest
        // did not declare a lookup for, and `nil` is the truth about it.
        lookup: (name) =>
          Object.hasOwn(bindings, name)
            ? jsonToGuest(bindings[name], arena.put)
            : { tag: "nil" },
        // `sendAt` is something a compiled card can do, so it is collected
        // rather than swallowed. `path` arrives as lifted `path-step`
        // variants; `cardguest.mbt` turns them back into steps.
        sendAt: (path, name, args) =>
          control.push({
            kind: "sendAt",
            path: path.map(stepToJson),
            name,
            args: args.map((a) => guestToJson(a, arena.cells)),
          }),
        // The routed four. A compiled card emits every one of these — `intent lex
        // 'loadQuote'` is step 7 of the tutorial — and an import the host does
        // not implement is an instantiation error, not a silently dropped
        // effect.
        //
        // `opts` is WIT `intent-opts` lifted, and it crosses as the same JSON
        // `dyncomp/host/wasm/loader.mjs` sends: a `route` list of leg names, an
        // empty one meaning "the card wrote no leg" for the host to resolve.
        intent: (name, args, opts) =>
          control.push({
            kind: "intent",
            name,
            args: args.map((a) => guestToJson(a, arena.cells)),
            opts: optsToJson(opts),
          }),
        // An empty `args` means "the ones that arrived", which is the same
        // thing `forward` with no arguments means — so there is no third state
        // and nothing to carry a discriminant for.
        forward: (args, opts) =>
          control.push({
            kind: "forward",
            args: args.map((a) => guestToJson(a, arena.cells)),
            opts: optsToJson(opts),
          }),
        // ONE value each, not a list of them: the walk addresses a `reply`, so
        // there is nothing for it to name and nothing to amend.
        reply: (v) =>
          control.push({ kind: "reply", value: guestToJson(v, arena.cells) }),
        fail: (e) =>
          control.push({ kind: "fail", value: guestToJson(e, arena.cells) }),
        // Still nothing a card can emit: the generator has no `intentAt`,
        // and a stub is what an unreachable import costs.
        intentAt: () => {},
        // A same-bundle child factory. The token IS the handle in the table
        // beside this one — the only instance-token space a card has.
        //
        // The Component Model forbids re-entering a component while a call
        // into it is active, so the token is RESERVED here and the child is
        // constructed after the current guest call returns. `drainChildren`
        // runs before `arena.clear()`, because the args captured here are
        // arena cells and clearing first would build the child out of nothing.
        makeInstance: (component, args) => {
          const h = nextHandle++;
          table.set(h, { inst: null, comp: component });
          pendingChildren.push({ handle: h, component, args });
          return BigInt(h);
        },
        dropInstance: (token) => {
          table.delete(Number(token));
        },
      },
    },
    descriptor,
  );

  const to = (j) => jsonToGuest(j, arena.put);
  const from = (v) => guestToJson(v, arena.cells, table);

  // KEYED, and it used to be one global object. That was fine while exactly one
  // compiled card existed on a page — the "run the module" pane, pressed
  // deliberately — and stops being fine now that mounting ANY card compiles it:
  // a page with two `<mb-card>` embeds has two modules, each with its own
  // instance table, and a second `loadGuest` would otherwise leave the first
  // card's handles pointing into a table that is no longer there.
  //
  // The key is the mount point's element id, which is what makes it unique: an
  // element holds one card.
  globalThis.__cardguest = globalThis.__cardguest ?? {};
  globalThis.__cardguest[key] = {
    /// Everything the card has logged since this was last asked, and empty
    /// afterwards. Taken rather than read, so a driver reads one step's lines
    /// without also reading the previous step's.
    takeLog() {
      const out = logLines.join("\n");
      logLines.length = 0;
      return out;
    },
    /** Release one instance. */
    dropInstance(handle) {
      table.delete(handle);
    },
    /**
     * Keep only these handles, and answer how many went.
     *
     * The sweep half of the collector. A handle a successor replaced is
     * collected by the host's own GC; one that was simply DROPPED — a row
     * removed from a list — was never superseded by anything, and nothing was
     * watching the place it left. Reachability is the only thing that finds it,
     * and the host holds the root.
     *
     * A child whose token has been handed out but whose instance is still
     * queued is NOT reachable yet and must not be swept — it is about to be
     * built into the very tree the walk is reading.
     */
    /** How many instances the table holds. For a test that watches it grow. */
    size() {
      return table.size;
    },
    retain(handlesJson) {
      const keep = new Set(JSON.parse(handlesJson));
      for (const { handle } of pendingChildren) keep.add(handle);
      let gone = 0;
      for (const h of [...table.keys()]) {
        if (!keep.has(h)) {
          table.delete(h);
          gone++;
        }
      }
      return gone;
    },
    create(component, argsJson) {
      const args = Object.entries(JSON.parse(argsJson)).map(([k, v]) => [k, to(v)]);
      const h = register(new root.guest.Instance(component, args), component);
      drainChildren();
      arena.clear();
      return h;
    },
    getField(handle, name) {
      const v = instOf(handle)?.getField(name);
      const out = v === undefined ? "" : JSON.stringify(from(v));
      drainChildren();
      arena.clear();
      return out;
    },
    dispatch(handle, bucketInt, name, argsJson, bindingsJson) {
      control = [];
      // What the host resolved this component's declared lookups to, for the
      // duration of THIS call. `control.lookup` reads them and nothing else —
      // see the WIT: an effect is applied after the call, and a value a
      // handler is in the middle of using cannot wait for that.
      bindings = bindingsJson ? JSON.parse(bindingsJson) : {};
      const inst = instOf(handle);
      if (!inst) return JSON.stringify({ handled: false, next: null, msgs: [] });
      const result = bucketInt === 1
        ? inst.handleIntent(name, JSON.parse(argsJson).map(to))
        : inst.handleMessage(name, JSON.parse(argsJson).map(to));
      const out = JSON.stringify({
        handled: result.tag !== "unhandled",
        next:
          result.tag === "changed"
            ? register(result.val, compOf(handle))
            : null,
        msgs: control,
      });
      drainChildren();
      arena.clear();
      control = [];
      bindings = {};
      return out;
    },
    // `bindings` for the reason `dispatch` has them, resolved for the RENDER
    // position instead of the dispatch one: a `compute`, a `pred`, a `@when`
    // or an `enrich` that reads `*name` compiles `control.lookup`, and this is
    // the only thing that answers it. Set and cleared around the call exactly
    // as `dispatch` does — a binding must not outlive the call it was resolved
    // for.
    renderCall(handle, category, name, argsJson, bindingsJson) {
      const inst = instOf(handle);
      if (!inst) return "";
      bindings = bindingsJson ? JSON.parse(bindingsJson) : {};
      try {
        const args = JSON.parse(argsJson).map(to);
        const v = category === "when" ? { tag: "boolean", val: inst.when(name, args) }
          : category === "enrich" ? inst.enrich(name, args)
          : category === "enrichScope" ? inst.enrichScope(name)
          : inst.compute(name, args);
        const out = JSON.stringify(from(v));
        drainChildren();
        arena.clear();
        return out;
      } finally {
        bindings = {};
      }
    },
    getProperty(handle, name) {
      const v = instOf(handle)?.getProperty(name);
      const out = v === undefined ? "" : JSON.stringify(from(v));
      drainChildren();
      arena.clear();
      return out;
    },
    setProperty(handle, name, valueJson) {
      const inst = instOf(handle);
      if (!inst) return JSON.stringify({ tag: "missing" });
      const result = inst.setProperty(name, to(JSON.parse(valueJson)));
      const out = result.tag === "changed"
        ? { tag: "changed", next: register(result.val, compOf(handle)) }
        : { tag: result.tag };
      drainChildren();
      arena.clear();
      return JSON.stringify(out);
    },
    withField(handle, name, valueJson) {
      const inst = instOf(handle);
      if (!inst) return -1;
      const next = inst.withField(name, to(JSON.parse(valueJson)));
      drainChildren();
      arena.clear();
      return next === undefined ? -1 : register(next, compOf(handle));
    },
  };
  // The table above is NEW, and the collector's sweep keeps what each app on
  // the key could reach the last time it drained (`cardguest.mbt`,
  // `sweep_live`). Those are handles into the table this one replaced, and a
  // handle is a number: kept, they would pin whichever entries this table
  // happens to hand out the same numbers to. So the record goes with the table
  // it was about.
  globalThis.__tutucard?.resetSweep?.(key);
  return root;
}

// --- packing ---------------------------------------------------------------
//
// `scripts/pack-bundle.mjs` ported: the same hand-rolled 512-byte ustar
// writer, with `CompressionStream("gzip")` for `node:zlib` and `Uint8Array`
// for `Buffer`. The output is the archive shape the universal host page
// already accepts — `tutuca.json` plus one core wasm, and no executable
// JavaScript anywhere in it.
//
// Views ride inside the descriptor's manifest as `html` rather than as files
// beside it. `loader.mjs` hydrates a `src` into an `html` and leaves an `html`
// alone, so both shapes load; this one is what a page that never had files has.

const enc = new TextEncoder();

function tarHeader(name, size) {
  const h = new Uint8Array(512);
  const put = (s, at) => h.set(enc.encode(s), at);
  const octal = (n, len) => n.toString(8).padStart(len - 1, "0") + "\0";
  put(name, 0);
  put(octal(0o644, 8), 100);
  put(octal(0, 8), 108);
  put(octal(0, 8), 116);
  put(size.toString(8).padStart(11, "0") + "\0", 124);
  put(octal(0, 12), 136);
  put("        ", 148); // checksum placeholder: eight spaces, per POSIX
  put("0", 156);
  put("ustar\0", 257);
  put("00", 263);
  let sum = 0;
  for (const b of h) sum += b;
  put(sum.toString(8).padStart(6, "0") + "\0 ", 148);
  return h;
}

function buildTar(files) {
  const parts = [];
  let total = 0;
  for (const { name, data } of files) {
    const header = tarHeader(name, data.length);
    const pad = new Uint8Array((512 - (data.length % 512)) % 512);
    parts.push(header, data, pad);
    total += header.length + data.length + pad.length;
  }
  const end = new Uint8Array(1024); // two zero blocks = end of archive
  parts.push(end);
  total += end.length;
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/**
 * The wasm as bytes.
 *
 * It crosses from MoonBit as base64 because a MoonBit extern cannot hand
 * JavaScript a byte array, and the page needs the real thing: to instantiate
 * it, and to put it in the archive.
 */
export const b64ToBytes = (b64) =>
  Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

/**
 * Show a card: compile it, instantiate the module, mount an instance.
 *
 * THE ONE ASYNC STEP is the middle one. `__tutucard.compile` is synchronous and
 * so is `__tutucard.mountCompiled`, but `WebAssembly.compile` between them
 * answers a promise — which is why this sequence is here rather than on the
 * MoonBit side as one call. There used to be a `__tutucard.load` that did all
 * of it synchronously, because what it mounted was an INTERPRETED card and
 * there was no module to instantiate.
 *
 * Answers the shape the editor already reads, with the compiler's own two lists
 * added: what it `refused` and what the card `escaped` into Wax.
 *
 *   { ok: true,  component, mounted, issues, refusals, escapes, build }
 *   { ok: false, error, line, start, end }
 *
 * `build` is the compile report, for the panels that show the WAT, the WAX and
 * the download — so a caller that wants those does not compile a second time.
 *
 * `init` names one of the card's `tutuca/fixtures` fixtures. "" is not "no fixture"
 * — it is "nothing was named", and a card that marked one `default` has already
 * said what to show then. So the ordinary mount shows the card the way its
 * author meant it to be met.
 */
export async function mountCard(previewId, source, name, { allowWax = false, init = "" } = {}) {
  // The CHECKER first, and separately. A card being edited is usually a card
  // with something wrong with it, and the findings are what the editor
  // underlines — `compile` turns such a card away whole, which is right for a
  // module a host will mount and wrong for a line somebody is halfway through.
  let checked;
  try {
    checked = JSON.parse(globalThis.__tutucard.check(source, name));
  } catch (e) {
    return { ok: false, error: String(e), line: 1, start: 0, end: 0 };
  }
  if (!checked.ok) return checked;

  let build;
  try {
    build = JSON.parse(globalThis.__tutucard.compile(source, name, allowWax));
  } catch (e) {
    build = { ok: false, error: String(e) };
  }
  if (!build.ok) {
    return { ...checked, mounted: false, build, error: build.error };
  }

  // An id that is not on the page answers `mounted: false` rather than
  // failing: an embed removed while a debounce was in flight is an ordinary
  // thing, not an error to report to a reader.
  if (!document.getElementById(previewId)) {
    globalThis.__tutucard.unmount(previewId);
    return { ...checked, mounted: false, build };
  }
  // Keyed by the mount point, so two cards on one page are two modules.
  await loadGuest(b64ToBytes(build.wasm), build.descriptor, previewId);
  const mounted = JSON.parse(
    globalThis.__tutucard.mountCompiled(
      previewId,
      JSON.stringify(build.manifest),
      init,
    ),
  );
  return {
    ...checked,
    mounted: mounted.ok === true,
    // A bundle the host refuses is a real failure and the reason is the whole
    // of what a reader can act on.
    error: mounted.ok === true ? undefined : mounted.error,
    diagnostics: mounted.diagnostics ?? [],
    refusals: build.refusals ?? [],
    escapes: build.escapes ?? [],
    build,
  };
}

/**
 * Drive a card's scenes and answer what each one did.
 *
 * The same first three steps `mountCard` takes — check, compile, instantiate —
 * and then `drive` instead of `mountCompiled`. The difference is where the
 * card lands: `mountCompiled` needs an element on a page, and this mounts on
 * the in-memory DOM, so nothing here touches `document` and the whole sequence
 * runs under `node` against the same bundle that serves the page.
 *
 * That is the point rather than a bonus. A card can be shown, and showing it
 * proves it renders; until something pressed a button there was no way to find
 * out what it DID. This presses the buttons the card's own
 * `<script type="tutuca/test">` block names, and hands back the rendered HTML.
 *
 * `scenes` overrides that block — pass a JSON string to drive a card that
 * declares no tests at all, which is the situation anything that just
 * GENERATED a card is in.
 *
 *   { ok, ran, failed, scenes: { "<name>": { ok, html, state, steps, … } } }
 *   { ok: false, error, line, start, end }   // it did not compile
 *
 * A scene with no `expect` in it never fails and still answers its `html` and
 * `state`. Writing the drive first and reading what happened is the intended
 * order.
 */
export async function driveCard(source, name, { allowWax = false, scenes = "", key = "drive" } = {}) {
  let checked;
  try {
    checked = JSON.parse(globalThis.__tutucard.check(source, name));
  } catch (e) {
    return { ok: false, error: String(e), line: 1, start: 0, end: 0 };
  }
  if (!checked.ok) return checked;

  let build;
  try {
    build = JSON.parse(globalThis.__tutucard.compile(source, name, allowWax));
  } catch (e) {
    build = { ok: false, error: String(e) };
  }
  if (!build.ok) return { ...checked, ok: false, error: build.error, build };

  await loadGuest(b64ToBytes(build.wasm), build.descriptor, key);
  const report = JSON.parse(
    globalThis.__tutucard.drive(
      key,
      JSON.stringify(build.manifest),
      source,
      scenes,
    ),
  );
  // The compiler's own two lists travel with the report: a scene that fails
  // because its handler was REFUSED is not a scene that disagrees with the
  // component, and a reader with only the verdict cannot tell.
  return {
    ...report,
    issues: checked.issues ?? [],
    refusals: build.refusals ?? [],
    escapes: build.escapes ?? [],
    build,
  };
}

/**
 * The card's bytes as a `WebAssembly.Module`, for a caller that will instantiate
 * it more than once.
 *
 * Named rather than inlined so the reason for the split has somewhere to live:
 * compiling is the expensive half and instantiating is the cheap one, and a
 * gallery of a card's fixtures is the same module N times over.
 */
export const compileGuest = (bytes) => WebAssembly.compile(bytes);

/** A `.tutuca.tar.gz` for a compiled card, as a Blob. */
export async function packBundle(report, wasmBytes) {
  const descriptor = { ...report.descriptor, manifest: report.manifest };
  const files = [
    { name: "tutuca.json", data: enc.encode(JSON.stringify(descriptor)) },
    { name: descriptor.core, data: wasmBytes },
  ];
  const tar = buildTar(files);
  const gz = new Response(
    new Blob([tar]).stream().pipeThrough(new CompressionStream("gzip")),
  );
  return new Blob([await gz.arrayBuffer()], { type: "application/gzip" });
}
