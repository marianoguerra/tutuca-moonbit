// Mounting a `tgc` card, and downloading one.
//
// The OTHER backend, on the page. `tgc/emit` compiles a card to a core wasm
// module using the GC proposal and nothing else — no component model, no WIT,
// no archive — and this instantiates one and installs the same
// runtime and the module's exports on `globalThis.__tgcmod[key]`, and the host
// reads a `tg_val` off them directly — so the whole host above it (views,
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
import { makeValues } from "../../tgc/host/values.mjs";

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

  // A CHILD crossing to the host. The host cannot hold a GC reference, so it
  // holds a handle and asks for the instance back through
  // `Module::wrap_instance` — which is the marker `cardguest.mbt` already reads,
  // and the reason a card can put a sibling in a field at all.
  //
  // The component NAME travels with it because a handle says which instance,
  // not which kind, and the host needs the kind to wrap it. The MODULE travels
  // beside it for the same reason one step out: a component name is only unique
  // within a module, and the host resolving `Note` against whichever module
  // happened to be decoding is how a note came back wearing a hole's schema.
  // Text out of `tg_bytes`, and the manifest at the end. The only two things
  // this file still reads out of a value; everything else a card produces is
  // read by the HOST, in MoonBit, off the `tg_val` itself — no marker, no
  // handle, no JSON.
  const V = makeValues(rt);

  const control = [];
  const logLines = [];

  const effects = {
    eff_send: (name, args) => control.push(["send", name, rt.mk_list(args)]),
    // A PLACE, reified by the generator and walked by the host. The steps are
    // already in the host's own spelling — `{"field":…}`, `{"item":[seq,key]}`,
    // `{"at":[seq,i]}` — so this hands them over rather than translating them.
    eff_send_at: (path, name, args) =>
      control.push(["sendAt", path, name, rt.mk_list(args)]),
    eff_reply: (name, args) =>
      control.push(["sendReply", name, rt.mk_list(args)]),
    eff_answer: (v) => control.push(["reply", v]),
    eff_ask: (name, args, route) =>
      control.push(["intent", name, rt.mk_list(args), route]),
    eff_notify: (name, args, route) =>
      control.push(["intent", name, rt.mk_list(args), route]),
    eff_forward: (args, route) =>
      control.push(["forward", rt.mk_list(args), route]),
    eff_fail: (v) => control.push(["fail", v]),
    eff_drop: () => control.push(["stopPropagation"]),
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

  // A raw buffered entry, as the JSON surface's `msgs` shape. Only the JSON
  // half needs this, which is why it lives beside that half rather than in the
  // buffer.
  const { instance } = await WebAssembly.instantiate(bytes, {
    tut: { ...rt, ...effects },
  });
  const ex = instance.exports;

  // The host resolves this component's declared `lookup`s before it calls in
  // — for a dispatch and for a render call alike — and they ride in the call's
  // fifth slot, which is otherwise only used by a property write. That is how a
  // `*name` in a compiled handler reads the same value the view beside it does.
  globalThis.__tgcmod = globalThis.__tgcmod ?? {};
  // The buffer travels BESIDE the exports rather than on them: a WebAssembly
  // exports object is frozen, and a host that has to own the buffer cannot put
  // it there.
  globalThis.__tgcmod[key] = { rt, ex, control };
  // What the card has SAID, where a host that is not the playground can read
  // it. Same lines, same order; `takeLog` below drains the same array.
  globalThis.__cardlog = globalThis.__cardlog ?? {};
  globalThis.__cardlog[key] = logLines;

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
