// Compiler worker: drives @moonbit/moonc-worker (the in-browser MoonBit
// compiler, vendored as moonc-web.cjs) to compile a user package against the
// prebuilt tutuca-mb library and link it to a runnable module.
//
// moonc-web.cjs is a CommonJS module built for both Node and the browser: it
// only touches node:fs when it detects a Node runtime, so in a worker we just
// provide the CJS ambient names (module/exports/require/process) it expects.

self.process = { versions: {}, platform: "browser", cwd: () => "/", exit: () => {}, env: {} };
self.module = { exports: {} };
self.exports = self.module.exports;
self.require = (m) => {
  if (m === "constants") return {};
  throw new Error("moonc worker: unexpected require(" + m + ")");
};

let moonc = null;
let mooncSrc = null; // the compiler source text, fetched once and re-evaluated
// Every payload this worker has loaded, keyed by target:
//   { target, std:[[name,bytes]], lib:[[name,bytes]], direct:[[name,bytes]], cores:[bytes], userPkg }
// ONE worker serves the whole page — the standalone playground, or every
// <mb-playground> element on the landing page — and those callers do not agree
// on a backend: a reader can leave one embed on wasm-gc and another on js. So
// the payload is picked PER COMPILE from this map. Holding it as worker state
// instead means whichever init() ran last silently decides what everyone else
// compiles against, which surfaces as a wasm module handed to a JS mount (or
// the reverse) rather than as an error anyone can read.
const payloads = new Map();

// A failed compile leaves moonc UNUSABLE: on an error it calls process.exit,
// which this worker stubs out, so it returns mid-abort and every later
// buildPackage yields no core. It also accumulates diagnostics across calls,
// so a stale error would be reported forever. Both are fatal on the landing
// page, where one worker is shared by every <mb-playground>: a single broken
// edit would take down the whole page. So a failed compile marks the compiler
// dirty and the next one starts from a freshly evaluated instance (~5 MB of
// cached source, re-evaluated only on the error path).
let compilerDirty = false;
// how many diagnostics the accumulating array held after the last compile
let seenDiagnostics = 0;

const bytes = async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer());

// (Re)create the compiler from its CJS source: fetch + indirect-eval in global
// scope, so the ambient CJS names (module/exports/require) resolve.
// (importScripts surfaces any in-module error as an opaque NetworkError, so we
// avoid it.)
async function loadCompiler() {
  mooncSrc ??= await (await fetch("./moonc-web.cjs")).text();
  self.module = { exports: {} };
  self.exports = self.module.exports;
  (0, eval)(mooncSrc);
  moonc = self.module.exports;
  compilerDirty = false;
  seenDiagnostics = 0;
}

// The editor holds ONLY the component (a `build() -> @component.ModuleDef`); the
// target-specific boot glue is injected here as a second package file so one
// source compiles on both backends. The glue differs for a fundamental reason —
// the wasm/JS ABI boundary: js compiles to JS so `main` self-mounts and closures
// cross freely, whereas wasm-gc has no JS-callable `main` (JS calls exported
// wrappers) and closures can't cross (events delegate through exported
// `on_event`). Kept in its own file so user diagnostics keep their line numbers.
const BOOT = {
  js: `fn main {
  @host.mount(build(), "app")
}
`,
  "wasm-gc": `pub fn mount() -> Unit { @host_wasm.mount(build(), "app") }
pub fn on_event(ev : @core.Any) -> Unit { @host_wasm.on_event(ev) }
pub fn state_json() -> String { @host_wasm.state_json() }
pub fn classes_json() -> String { @host_wasm.classes_json() }
pub fn activity_json() -> String { @host_wasm.activity_json() }
fn main {

}
`,
};

async function init(manifestUrl, target) {
  // Already loaded: hand back the same summary without touching the compiler.
  // (Re-evaluating it here would throw away the warm instance for nothing.)
  const loaded = payloads.get(target);
  if (loaded) return loaded.summary;
  await loadCompiler();
  const manifest = await (await fetch(manifestUrl)).json();
  const m = manifest.targets[target];
  if (!m) throw new Error("no manifest for target " + target);
  const base = `./fs/${target}/`;
  const load = (list) => Promise.all(list.map(async (p) => [p, await bytes(base + p)]));
  const [std, lib, cores] = await Promise.all([
    load(m.std),
    load(m.lib),
    Promise.all(m.linkOrder.map((p) => bytes(base + p))),
  ]);
  const directSet = new Set(m.direct);
  payloads.set(target, {
    target,
    std,
    lib: lib.filter(([p]) => !directSet.has(p)),
    direct: lib.filter(([p]) => directSet.has(p)),
    cores,
    userPkg: m.userPkg,
    summary: { std: std.length, lib: lib.length, cores: cores.length },
  });
  return payloads.get(target).summary;
}

// `viewsCode` is the module `tutuca gen-views` produced from the View tab
// (empty when that tab is unused). It joins the user's package as another
// file rather than another package, which is why the component tab can name
// CounterMsg / counter_main_view with no import at all — same package, same
// scope. Kept in its own file so the user's diagnostics keep their line
// numbers, exactly like _boot.mbt.
async function compile(userCode, viewsCode, viewsIrCode, target) {
  const t0 = Date.now();
  // the previous compile failed: start from a clean compiler (see above)
  if (compilerDirty) await loadCompiler();
  // Resolve the payload AFTER the awaits above and hold it in a local: message
  // handling is async, so another caller's compile can interleave here, and the
  // rest of this function must see one target's .mi/.core set throughout.
  const fs = payloads.get(target);
  if (!fs) throw new Error("worker has no payload for target " + target + " (init first)");
  const boot = BOOT[fs.target] || BOOT.js;
  const files = [["main.mbt", userCode], ["_boot.mbt", boot]];
  if (viewsCode) files.push(["_views.mbt", viewsCode]);
  if (viewsIrCode) files.push(["_views_ir.mbt", viewsIrCode]);
  const bp = moonc.buildPackage({
    mbtFiles: files,
    miFiles: fs.direct,
    indirectImportMiFiles: fs.lib,
    stdMiFiles: fs.std,
    target: fs.target,
    pkg: fs.userPkg,
    pkgSources: [fs.userPkg + ":."],
    isMain: true,
    errorFormat: "human",
    enableValueTracing: false,
    noOpt: false,
  });
  const all = bp.diagnostics || [];
  const diagnostics = all.slice(seenDiagnostics);
  seenDiagnostics = all.length;
  if (!bp.core) {
    compilerDirty = true;
    return { ok: false, target: fs.target, diagnostics, ms: Date.now() - t0 };
  }
  // js links to a runnable JS module (nothing to export — `main` self-mounts).
  // wasm-gc has no callable `main` from JS: the host facade is driven through
  // exported wrappers, so those must be named as link exports.
  const wasm = fs.target === "wasm-gc";
  const exportedFunctions = wasm
    ? ["mount", "on_event", "state_json", "classes_json", "activity_json"]
    : [];
  // On wasm-gc a MoonBit String lowers either as a JS-String-Builtins externref
  // or as MoonBit's native `(ref 1)` char array, and the choice is made HERE, at
  // link time, for every core in the set at once. The baked cores were built for
  // the js-string ABI (as are the shipped wasm demos), so linking without this
  // mixes the two and the module fails to validate — `array.new_fixed expected
  // type externref, found local.get of type (ref 1)`. `runtime.js` instantiates
  // with the matching { builtins: ["js-string"], importedStringConstants: "_" }.
  const stringAbi = wasm ? { useJsBuiltinString: true, importedStringConstants: "_" } : {};
  const lk = moonc.linkCore({
    coreFiles: [...fs.cores, bp.core],
    main: fs.userPkg,
    pkgSources: [fs.userPkg + ":."],
    target: fs.target,
    exportedFunctions,
    ...stringAbi,
    outputFormat: "wasm",
    testMode: false,
    debug: false,
    noOpt: false,
    sourceMap: false,
    sources: {},
    stopOnMain: false,
  });
  return { ok: true, target: fs.target, diagnostics, result: lk.result, ms: Date.now() - t0 };
}

self.onmessage = async (e) => {
  const { id, kind, args } = e.data;
  try {
    if (kind === "init") self.postMessage({ id, ok: true, value: await init(args.manifest, args.target) });
    else if (kind === "compile") {
      const r = await compile(args.code, args.views, args.viewsIr, args.target);
      // transfer the linked bytes to avoid a copy
      self.postMessage({ id, ok: true, value: r }, r.result ? [r.result.buffer] : []);
    }
  } catch (err) {
    // a throw mid-compile leaves the compiler in the same unusable state a
    // failed compile does
    compilerDirty = true;
    self.postMessage({ id, ok: false, error: String(err && err.stack || err) });
  }
};
