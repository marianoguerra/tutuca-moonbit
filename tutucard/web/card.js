// Mounting a `tgc` card, and downloading one.
//
// The OTHER backend, on the page. `tgc/emit` compiles a card to a core wasm
// module using the GC proposal and nothing else — no component model, no WIT,
// no archive — and this instantiates one and installs the same
// `globalThis.__cardguest[key]` surface the old backend installs, so
// `cardguest.mbt` mounts it unchanged and the whole host above it (views,
// renderer, dispatch, the transactor) is the host it already was.
//
// That reuse is the point rather than a shortcut. What changed is the guest
// boundary and nothing above it, which is exactly the claim the format makes.
//
// Two things are simpler here than in the component-model format this replaced,
// and both are the format
// rather than this file being clever:
//
//   - THERE IS NO ARENA. A compound value crossed the old boundary as a u64
//     handle into a host-side table valid for the duration of one call, because
//     WIT has no recursive types. Here a value is a reference: it is handed
//     over, and it lives as long as somebody holds it.
//   - THERE IS NO INSTANCE TABLE TO SWEEP. An instance is a GC struct; the
//     engine collects it. The handle map below exists only because MoonBit's
//     js target passes integers across this seam, not because anything needs
//     to be kept alive.
import { makeValues, OP } from "../../tgc/host/values.mjs";

/** The runtime module, instantiated once per page. `tut` is shared. */
let runtimePromise = null;

function loadRuntime() {
  if (!runtimePromise) {
    runtimePromise = (async () => {
      const report = JSON.parse(globalThis.__tutucard.runtimeWasm());
      if (!report.ok) throw new Error(report.error);
      const bytes = b64ToBytes(report.wasm);
      const { instance } = await WebAssembly.instantiate(bytes, {});
      return instance.exports;
    })();
  }
  return runtimePromise;
}

export const b64ToBytes = (b64) =>
  Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

// The route, as the one integer the emitter writes it as. Written RESOLVED —
// a bare `ask` is `dyn lex` — because the default route is exactly the kind of
// thing two backends can agree to disagree about while every case with an
// explicit route passes.
const ROUTE_LEGS = { 1: ["dyn"], 2: ["lex"], 3: ["dyn", "lex"], 4: ["lex", "dyn"] };

/**
 * Instantiate a compiled card and install the guest surface for `cardguest.mbt`.
 *
 * The same five-ish calls the old backend installs, under the same key, so
 * nothing above this line knows which backend it is talking to.
 */
export async function loadGuest(bytes, key = "default", { runtime } = {}) {
  // The runtime is a parameter so this is drivable with no page: `tgc/test`
  // instantiates one and hands it over, which is what lets the guest bridge be
  // tested rather than only looked at.
  const rt = runtime ?? (await loadRuntime());

  // Instances by integer, because MoonBit's js target passes integers across
  // this seam. The engine owns the instance; this only names it.
  const table = new Map();
  // …and the same instance keeps the same NAME. `onComp` runs every time a
  // child crosses, which is once per render per row, so minting a fresh handle
  // each time gave one live row two or three entries — the collector then freed
  // the ones the newest render had not just made, and the count sat at a
  // multiple of the rows rather than at the rows. A handle is an identity here,
  // not a ticket.
  const byInstance = new Map();
  const table_delete = (h) => {
    const inst = table.get(h);
    if (inst !== undefined && byInstance.get(inst) === h) byInstance.delete(inst);
    return table.delete(h);
  };
  let next = 1;
  const put = (inst) => {
    const seen = byInstance.get(inst);
    if (seen !== undefined) return seen;
    const h = next++;
    table.set(h, inst);
    byInstance.set(inst, h);
    return h;
  };

  // A CHILD crossing to the host. The host cannot hold a GC reference, so it
  // holds a handle and asks for the instance back through
  // `Bundle::wrap_instance` — which is the marker `cardguest.mbt` already reads,
  // and the reason a card can put a sibling in a field at all.
  //
  // The component NAME travels with it because a handle says which instance,
  // not which kind, and the host needs the kind to wrap it.
  const V = makeValues(rt, {
    onComp: (inst) => ({
      $dyn: { handle: put(inst), comp: V.text(instComponent(inst)) },
    }),
    ofHandle: (h) => table.get(h) ?? null,
  });

  // A component's own name, off the instance's descriptor.
  //
  // `desc` is that component's slice of the module's manifest, so the name is
  // under `name` — the manifest's spelling. There is one description of a
  // component now and this reads it, rather than a second small map written
  // beside it that could say something else.
  const instComponent = (inst) => {
    const desc = rt.inst_desc(inst);
    for (let i = 0; i < rt.map_len(desc); i++) {
      if (V.text(rt.map_key(desc, i)) === "name") {
        return rt.as_str(rt.map_val(desc, i));
      }
    }
    return rt.bytes_new(0);
  };

  // What the card asked the host to do, for the duration of one dispatch. The
  // HOST buffers rather than the guest, because the host is what brackets the
  // call and therefore knows when it ended — an effect performed before a
  // statement that abandons is discarded with the transition, and only this
  // side can tell that the transition abandoned.
  let control = [];
  const logLines = [];

  const opts = (route) => ({
    route: ROUTE_LEGS[route] ?? [],
    onOk: null,
    onError: null,
    onUnhandled: null,
    livePath: false,
  });

  const effects = {
    eff_send: (name, args) =>
      control.push({ kind: "send", name: V.text(name), args: argsOf(args) }),
    // A PLACE, reified by the generator and walked by the host. The steps are
    // already in the host's own spelling — `{"field":…}`, `{"item":[seq,key]}`,
    // `{"at":[seq,i]}` — so this hands them over rather than translating them.
    eff_send_at: (path, name, args) =>
      control.push({
        kind: "sendAt",
        path: V.toJson(path) ?? [],
        name: V.text(name),
        args: argsOf(args),
      }),
    eff_reply: (name, args) =>
      control.push({ kind: "sendReply", name: V.text(name), args: argsOf(args) }),
    eff_answer: (v) => control.push({ kind: "reply", value: V.toJson(v) ?? null }),
    eff_ask: (name, args, route) =>
      control.push({
        kind: "intent",
        name: V.text(name),
        args: argsOf(args),
        opts: opts(route),
      }),
    eff_notify: (name, args, route) =>
      control.push({
        kind: "intent",
        name: V.text(name),
        args: argsOf(args),
        opts: opts(route),
      }),
    eff_forward: (args, route) =>
      control.push({ kind: "forward", args: argsOf(args), opts: opts(route) }),
    eff_fail: (v) => control.push({ kind: "fail", value: V.toJson(v) ?? null }),
    eff_drop: () => control.push({ kind: "stopPropagation" }),
    // What a DECLINED rule said. `takeLog` hands it to whoever is watching —
    // a scene asserting `expect: log`, or a person with the console open. It
    // goes to both, because a page a person is looking at and a driver reading
    // it headlessly want the same sentence.
    eff_log: (msg) => {
      const line = V.text(msg);
      logLines.push(line);
      console.warn(line);
    },
  };

  // `tg_vals` is a bare array, and the runtime's only reader for one is the
  // list accessor — so it is wrapped rather than given a second accessor that
  // would do the same thing under another name.
  const argsOf = (a) => {
    const asList = rt.mk_list(a);
    const out = [];
    for (let i = 0; i < rt.list_len(asList); i++) {
      out.push(V.toJson(rt.list_at(asList, i)) ?? null);
    }
    return out;
  };

  const { instance } = await WebAssembly.instantiate(bytes, {
    tut: { ...rt, ...effects },
  });
  const ex = instance.exports;

  // The host resolves this component's declared `lookup`s before it calls in
  // — for a dispatch and for a render call alike — and they ride in the call's
  // fifth slot, which is otherwise only used by a property write. That is how a
  // `*name` in a compiled handler reads the same value the view beside it does.
  const bindings = (json) => {
    if (!json) return null;
    let m;
    try {
      m = JSON.parse(json);
    } catch {
      return null;
    }
    if (!m || typeof m !== "object" || Array.isArray(m)) return null;
    return V.ofJson(m);
  };

  const call = (h, op, name, args, v = null) => {
    const inst = table.get(h);
    if (!inst) return null;
    return rt.call_op(inst, op, V.bytes(name), V.vals(args), v);
  };

  // A NEW table under this key, so whatever the collector recorded about the
  // last one is a set of handles into a table that no longer exists. Left in
  // place it is not merely stale, it is wrong: handles restart at 1 here, so
  // an old record names live rows of the new table and pins them forever. The
  // sweep keeps the UNION of every app registered under a key, so one drive
  // per key never notices and a second one leaks the first one's whole tree.
  //
  // Guarded because `loadGuest` is drivable with no page at all — `tgc/test`
  // hands in its own runtime and installs no `__tutucard`.
  globalThis.__tutucard?.resetSweep?.(key);

  globalThis.__cardguest = globalThis.__cardguest ?? {};
  globalThis.__cardguest[key] = {
    takeLog() {
      const out = logLines.join("\n");
      logLines.length = 0;
      return out;
    },
    dropInstance(handle) {
      table_delete(handle);
    },
    size() {
      return table.size;
    },
    retain(handlesJson) {
      const keep = new Set(JSON.parse(handlesJson));
      let gone = 0;
      for (const h of [...table.keys()]) {
        if (!keep.has(h)) {
          table_delete(h);
          gone++;
        }
      }
      return gone;
    },
    create(component, argsJson) {
      const inst = ex["tgc.make"](V.bytes(component), V.ofJson(JSON.parse(argsJson)));
      return inst ? put(inst) : -1;
    },
    getField(handle, name) {
      const inst = table.get(handle);
      if (!inst) return "";
      const v = rt.get_field(inst, V.bytes(name));
      const j = V.toJson(v);
      return j === undefined ? "" : JSON.stringify(j);
    },
    dispatch(handle, bucketInt, name, argsJson, bindingsJson) {
      control = [];
      const args = JSON.parse(argsJson).map(V.ofJson);
      const op = bucketInt === 1 ? OP.HANDLE_INTENT : OP.HANDLE_MESSAGE;
      const answer = call(handle, op, name, args, bindings(bindingsJson));
      const out = JSON.stringify({
        // Null is "it did not happen": a rule declined, or an operation had no
        // answer. `unhandled` and `unchanged` are the same answer to this host
        // — no successor — and the card compiler does not distinguish them.
        handled: answer !== null,
        next: answer === null ? null : put(rt.as_inst(answer)),
        msgs: control,
      });
      control = [];
      return out;
    },
    renderCall(handle, category, name, argsJson, bindingsJson) {
      const op = category === "when"
        ? OP.WHEN
        : category === "enrich"
        ? OP.ENRICH
        : category === "enrichScope"
        ? OP.ENRICH_SCOPE
        : OP.COMPUTE;
      const args = JSON.parse(argsJson).map(V.ofJson);
      const answer = call(handle, op, name, args, bindings(bindingsJson));
      const j = V.toJson(answer);
      return j === undefined ? "" : JSON.stringify(j);
    },
    getProperty(handle, name) {
      const answer = call(handle, OP.GET_PROPERTY, name, []);
      const j = V.toJson(answer);
      return j === undefined ? "" : JSON.stringify(j);
    },
    setProperty(handle, name, valueJson) {
      const answer = call(
        handle,
        OP.SET_PROPERTY,
        name,
        [],
        V.ofJson(JSON.parse(valueJson)),
      );
      return JSON.stringify(
        answer === null
          ? { tag: "missing" }
          : { tag: "changed", next: put(rt.as_inst(answer)) },
      );
    },
    withField(handle, name, valueJson) {
      const answer = call(
        handle,
        OP.WITH_FIELD,
        name,
        [],
        V.ofJson(JSON.parse(valueJson)),
      );
      return answer === null ? -1 : put(rt.as_inst(answer));
    },
  };
  // `tgc.describe` is the manifest, as a value. Read once, here, so a caller
  // that mounts does not have to know it could have come from anywhere else.
  return { exports: ex, runtime: rt, manifest: V.toJson(ex["tgc.describe"]()) };
}

/**
 * Check, compile, instantiate and mount — the whole edit loop, `tgc` side.
 *
 * The one asynchronous step is the middle: `__tutucard.compile` is
 * synchronous and so is `mountCompiled`, and `WebAssembly.instantiate` between
 * them is not. That is the same shape `mountCard` has, for the same reason.
 */
export async function mountCard(previewId, source, name, { init = "" } = {}) {
  let checked;
  try {
    checked = JSON.parse(globalThis.__tutucard.check(source, name));
  } catch (e) {
    return { ok: false, error: String(e) };
  }
  if (!checked.ok) return { ...checked, stage: "check" };

  const build = JSON.parse(globalThis.__tutucard.compile(source, name));
  if (!build.ok) return { ...build, stage: "compile" };

  // An id that is not on the page answers `mounted: false` rather than failing:
  // an embed removed while a debounce was in flight is an ordinary thing.
  if (!document.getElementById(previewId)) {
    globalThis.__tutucard.unmount(previewId);
    return { ...checked, mounted: false, build };
  }

  globalThis.__tutucard.unmount(previewId);
  const { manifest } = await loadGuest(b64ToBytes(build.wasm), previewId);
  // The manifest comes OUT OF THE MODULE, not out of the build beside it.
  // `build.manifest` is the same value — the compiler projects it to JSON for
  // tooling — but taking it from the instantiated module is what makes the
  // module the single source: one file, and no way for a card to arrive with
  // half of itself.
  const mounted = JSON.parse(
    globalThis.__tutucard.mountCompiled(
      previewId,
      JSON.stringify(manifest),
      init,
    ),
  );
  // `shell.js` reads `issues` off this to draw the gutter.
  return {
    ...checked,
    mounted: mounted.ok === true,
    error: mounted.ok === true ? undefined : mounted.error,
    diagnostics: mounted.diagnostics ?? [],
    refusals: build.refusals ?? [],
    build,
  };
}

/**
 * Compile and hand the module to the person.
 *
 * One file. There is no archive to build and no manifest to ship beside it:
 * the module carries its own (`tgc.describe`), which is what lets a toolchain
 * that has never heard of this page produce one.
 */
export function downloadModule(source, name) {
  const build = JSON.parse(globalThis.__tutucard.compile(source, name));
  if (!build.ok) return build;
  const blob = new Blob([b64ToBytes(build.wasm)], { type: "application/wasm" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${name || build.component || "card"}.wasm`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Late enough that the click has been serviced, early enough that the page
  // does not accumulate one object URL per download.
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return build;
}

/** The runtime module, for a page that wants to save that too. */
export async function downloadRuntime() {
  const report = JSON.parse(globalThis.__tutucard.runtimeWasm());
  if (!report.ok) return report;
  const blob = new Blob([b64ToBytes(report.wasm)], { type: "application/wasm" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "tutuca-rt.wasm";
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return report;
}

/**
 * Check, compile, instantiate and DRIVE — the same card, with no page.
 *
 * `mountCard` proves a card renders. This presses the buttons the card's own
 * `<script type="tutuca/test">` block names, and hands back the rendered HTML,
 * so what a build step and an agent can both check is what it DID.
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
export async function driveCard(source, name, { scenes = "", key = "drive" } = {}) {
  let checked;
  try {
    checked = JSON.parse(globalThis.__tutucard.check(source, name));
  } catch (e) {
    return { ok: false, error: String(e), line: 1, start: 0, end: 0 };
  }
  if (!checked.ok) return checked;

  let build;
  try {
    build = JSON.parse(globalThis.__tutucard.compile(source, name));
  } catch (e) {
    build = { ok: false, error: String(e) };
  }
  if (!build.ok) return { ...checked, ok: false, error: build.error, build };

  const { manifest } = await loadGuest(b64ToBytes(build.wasm), key);
  const report = JSON.parse(
    globalThis.__tutucard.drive(key, JSON.stringify(manifest), source, scenes),
  );
  // The compiler's refusal list travels with the report: a scene that fails
  // because its handler was REFUSED is not a scene that disagrees with the
  // component, and a reader with only the verdict cannot tell.
  return {
    ...report,
    issues: checked.issues ?? [],
    refusals: build.refusals ?? [],
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
