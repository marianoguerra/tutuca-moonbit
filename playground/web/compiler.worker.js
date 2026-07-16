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
let fs = null; // { std:[[name,bytes]], lib:[[name,bytes]], direct:[[name,bytes]], cores:[bytes], userPkg }

const bytes = async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer());

async function init(manifestUrl, target) {
  // Load the CJS compiler by fetching + indirect-eval in global scope, so the
  // ambient CJS names (module/exports/require) resolve. (importScripts surfaces
  // any in-module error as an opaque NetworkError, so we avoid it.)
  const src = await (await fetch("./moonc-web.cjs")).text();
  (0, eval)(src);
  moonc = self.module.exports;
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
  fs = {
    target,
    std,
    lib: lib.filter(([p]) => !directSet.has(p)),
    direct: lib.filter(([p]) => directSet.has(p)),
    cores,
    userPkg: m.userPkg,
  };
  return { std: std.length, lib: lib.length, cores: cores.length };
}

function compile(userCode) {
  const t0 = Date.now();
  const bp = moonc.buildPackage({
    mbtFiles: [["main.mbt", userCode]],
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
  if (!bp.core) return { ok: false, target: fs.target, diagnostics: bp.diagnostics, ms: Date.now() - t0 };
  // js links to a runnable JS module (nothing to export — `main` self-mounts).
  // wasm-gc has no callable `main` from JS: the host facade is driven through
  // exported wrappers, so those must be named as link exports.
  const exportedFunctions =
    fs.target === "wasm-gc" ? ["mount", "on_event", "state_json", "classes_json"] : [];
  const lk = moonc.linkCore({
    coreFiles: [...fs.cores, bp.core],
    main: fs.userPkg,
    pkgSources: [fs.userPkg + ":."],
    target: fs.target,
    exportedFunctions,
    outputFormat: "wasm",
    testMode: false,
    debug: false,
    noOpt: false,
    sourceMap: false,
    sources: {},
    stopOnMain: false,
  });
  return { ok: true, target: fs.target, diagnostics: bp.diagnostics, result: lk.result, ms: Date.now() - t0 };
}

self.onmessage = async (e) => {
  const { id, kind, args } = e.data;
  try {
    if (kind === "init") self.postMessage({ id, ok: true, value: await init(args.manifest, args.target) });
    else if (kind === "compile") {
      const r = compile(args.code);
      // transfer the linked bytes to avoid a copy
      self.postMessage({ id, ok: true, value: r }, r.result ? [r.result.buffer] : []);
    }
  } catch (err) {
    self.postMessage({ id, ok: false, error: String(err && err.stack || err) });
  }
};
