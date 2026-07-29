// End-to-end check for the playground's View tab: take the shipped examples,
// run the SAME view generator the page runs (viewgen.js), and hand the result
// to the SAME in-browser compiler the worker drives — with the generated
// modules as extra files of the user's package, exactly as
// compiler.worker.js does.
//
// This is the piece a headless test cannot otherwise reach: that the module
// `tutuca gen-views` emits actually compiles inside the playground's package,
// where there is no moon.pkg to declare imports and `@tutuca` is the
// module-root facade rather than core/.
//
// Covered: EVERY starter example the picker offers (starter.js) and every
// landing-site example pair (playground/site/examples/<name>.{mbt,html}) —
// those are what dist/index.html compiles in a visitor's browser. The starter
// examples are covered here and nowhere else: no moon package includes them
// and check-playground-examples.mjs reads only site/examples, so the API can
// move out from under them silently (it did — `component()` grew a `Fields`
// bound and lost `mutate~`, and all four went on shipping uncompilable).
//
// Both backends are driven. wasm-gc additionally VALIDATES the linked bytes
// (`new WebAssembly.Module`), because its one link-time flag is invisible
// everywhere else: the payload's cores use the JS-String-Builtins ABI, and a
// link that does not ask for it emits a module that compiles, links, reports no
// diagnostics, and then will not load in a browser. See WASM_TARGET_STATUS.md.
//
// Run after `node playground/build/assemble.mjs`:
//   node playground/build/check-viewgen-tab.mjs

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const OUT = join(REPO, "dist/playground");
const SITE_EXAMPLES = join(REPO, "playground/site/examples");

if (!existsSync(join(OUT, "manifest.json"))) {
  console.error("dist/playground missing — run: node playground/build/assemble.mjs");
  process.exit(1);
}

// --- the view generator, as the page loads it -------------------------------
const genSrc = readFileSync(join(OUT, "viewgen.js"), "utf8");
new Function(genSrc)(); // publishes globalThis.__tutucaViewgen

// The driver reads the fallback component name from a `<!-- name: X -->`
// comment; a view file that names its templates ignores it.
const NAME_RE = /<!--\s*name:\s*([A-Za-z]\w*)\s*-->/;
const generate = (html) => {
  const name = (NAME_RE.exec(html) || [, "View"])[1];
  const r = JSON.parse(globalThis.__tutucaViewgen(html, name));
  if (!r.ok) throw new Error("generation failed: " + r.error);
  if (!r.ir) throw new Error("expected a compiled tree (a macro blocks it?)");
  return { name, ...r };
};

// --- the cases: the starter example + the landing site's examples -----------
const cases = [];

// Every picker entry with a View tab. (The one runtime-view escape-hatch
// example is a plain string with no view; it has no generated module, so
// there is nothing for THIS check to drive — its compile is covered by
// check-playground-examples.mjs' sibling scaffold instead.)
const starterSrc = readFileSync(join(OUT, "starter.js"), "utf8");
const window = {};
new Function("window", starterSrc)(window);
const withViews = Object.entries(window.EXAMPLES).filter(([, ex]) => ex && ex.view);
if (!withViews.length) throw new Error("starter has no view-tab example");
for (const [name, ex] of withViews) {
  cases.push({ label: `starter:${name}`, code: ex.code, html: ex.view });
}

for (const file of readdirSync(SITE_EXAMPLES).filter((f) => f.endsWith(".mbt")).sort()) {
  const html = join(SITE_EXAMPLES, file.replace(/\.mbt$/, ".html"));
  // an example with no view file is a runtime-view escape hatch: nothing to
  // generate, and check-playground-examples.mjs already compiles it
  if (!existsSync(html)) continue;
  cases.push({
    label: `site:${file}`,
    code: readFileSync(join(SITE_EXAMPLES, file), "utf8"),
    html: readFileSync(html, "utf8"),
  });
}

// generate once — the same generated module is compiled for every backend
for (const c of cases) c.gen = generate(c.html);

// --- the in-browser compiler, as the worker drives it -----------------------
globalThis.process = process;
// A failed compile leaves moonc UNUSABLE — on an error it calls process.exit,
// which returns mid-abort here, so every later buildPackage yields no core and
// reports the FIRST failure's diagnostics forever. The worker handles this with
// `compilerDirty` + a fresh evaluation (see compiler.worker.js); do the same,
// or one stale example turns every case after it into a false failure.
const require = createRequire(import.meta.url);
const MOONC = join(OUT, "moonc-web.cjs");
const loadCompiler = () => {
  delete require.cache[require.resolve(MOONC)];
  return require(MOONC);
};
let moonc = loadCompiler();
const manifest = JSON.parse(readFileSync(join(OUT, "manifest.json"), "utf8"));

// The boot glue compiler.worker.js injects, per backend. Kept in step with the
// BOOT table there — a drift makes this check pass on code the page can't run.
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
const WASM_EXPORTS = ["mount", "on_event", "state_json", "classes_json", "activity_json"];

// Load the .mi/.core payload a backend links against.
function payload(target) {
  const m = manifest.targets[target];
  const base = join(OUT, "fs", target);
  const load = (list) => list.map((p) => [p, new Uint8Array(readFileSync(join(base, p)))]);
  const directSet = new Set(m.direct);
  const lib = load(m.lib);
  return {
    userPkg: m.userPkg,
    direct: lib.filter(([p]) => directSet.has(p)),
    indirect: lib.filter(([p]) => !directSet.has(p)),
    std: load(m.std),
    cores: m.linkOrder.map((p) => new Uint8Array(readFileSync(join(base, p)))),
  };
}

// What a linked artifact has to be for the page to run it. js: a JS module the
// preview iframe imports. wasm-gc: a module the ENGINE accepts, instantiated
// with the js-string options runtime.js uses — that is the whole point of
// validating here rather than trusting a clean link.
function checkArtifact(target, bytes) {
  if (target !== "wasm-gc") {
    const js = new TextDecoder().decode(bytes);
    if (!js.includes("function")) throw new Error("linked output does not look like JS");
    return `${js.length} B JS`;
  }
  const mod = new WebAssembly.Module(bytes, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  const exports = new Set(WebAssembly.Module.exports(mod).map((e) => e.name));
  const missing = WASM_EXPORTS.filter((n) => !exports.has(n));
  if (missing.length) throw new Error("linked module is missing exports: " + missing.join(", "));
  // Under the js-string builtins the string ops are engine-provided, so what is
  // left must be exactly the surface runtime.js supplies. Anything else would
  // fail at instantiate in the browser, which this check cannot reach.
  const imports = [...new Set(WebAssembly.Module.imports(mod).map((i) => i.module))].sort();
  const expected = ["console", "jscore", "tdom"];
  const unexpected = imports.filter((i) => !expected.includes(i));
  if (unexpected.length) {
    throw new Error("linked module imports an unknown namespace: " + unexpected.join(", "));
  }
  return `${bytes.length} B wasm, imports ${imports.join("/")}`;
}

// moonc's diagnostics accumulate across buildPackage calls in one process, so
// each case reports only what its own compile added.
let seenDiagnostics = 0;
const resetCompiler = () => {
  moonc = loadCompiler();
  seenDiagnostics = 0;
};

function checkTarget(target) {
  const fs = payload(target);
  // start each backend from a fresh compiler: moonc-web carries state across
  // calls, and one long run has been seen to end in an OCaml Stack_overflow
  // that has nothing to do with the code being compiled
  resetCompiler();
  let failed = 0;
  console.log(`\n── target ${target} ──`);
  for (const c of cases) {
    const { gen } = c;
    process.stdout.write(
      `${c.label}: generated ${gen.name} (${gen.module.length} B types + ${gen.ir.length} B tree) … `,
    );

    const bp = moonc.buildPackage({
      mbtFiles: [
        ["main.mbt", c.code],
        ["_boot.mbt", BOOT[target]],
        ["_views.mbt", gen.module],
        ["_views_ir.mbt", gen.ir],
      ],
      miFiles: fs.direct,
      indirectImportMiFiles: fs.indirect,
      stdMiFiles: fs.std,
      target,
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
    // errors only — a warning (unused helper, …) is what the page shows in its
    // diagnostics pane and still runs, so it must not fail the gate
    const errs = diagnostics.filter((d) => /\[E\d/.test(d) && !/Warning/.test(d));
    if (!bp.core || errs.length) {
      console.log("FAILED");
      console.error(`\nthe generated module does not compile in the playground:\n`);
      console.error(diagnostics.join("\n\n"));
      failed++;
      resetCompiler(); // start the next case clean (see above)
      continue;
    }

    // Link too: a package can type-check and still fail to link (a missing core
    // in the closure), and the page's next step after compile is exactly this.
    // On wasm-gc the string ABI is chosen HERE, for every core at once, and it
    // must match what runtime.js instantiates with — link without it and the
    // bytes mix js-string `externref` with MoonBit's native `(ref 1)` array.
    try {
      const lk = moonc.linkCore({
        coreFiles: [...fs.cores, bp.core],
        main: fs.userPkg,
        pkgSources: [fs.userPkg + ":."],
        target,
        exportedFunctions: target === "wasm-gc" ? WASM_EXPORTS : [],
        ...(target === "wasm-gc"
          ? { useJsBuiltinString: true, importedStringConstants: "_" }
          : {}),
        outputFormat: "wasm",
        testMode: false,
        debug: false,
        noOpt: false,
        sourceMap: false,
        sources: {},
        stopOnMain: false,
      });
      console.log(`ok — compiled + linked (${checkArtifact(target, lk.result)})`);
    } catch (e) {
      console.log("FAILED");
      console.error(`\nthe linked artifact is not runnable:\n\n${e && e.message || e}\n`);
      failed++;
      resetCompiler();
      continue;
    }
    if (diagnostics.length) {
      console.log(diagnostics.map((d) => "  " + d).join("\n"));
    }
  }
  console.log(`${cases.length - failed}/${cases.length} view tabs compile + link on ${target}`);
  return failed;
}

// wasm-gc is absent from a JS_ONLY=1 payload; that is a valid build, so say the
// backend went unchecked rather than failing or passing silently.
const targets = ["js", "wasm-gc"].filter((t) => {
  if (manifest.targets[t]) return true;
  console.log(`note: no ${t} payload in this build — skipping (assembled with JS_ONLY=1?)`);
  return false;
});

let failed = 0;
for (const t of targets) failed += checkTarget(t);
console.log(`\n${failed ? `${failed} FAILED` : "all ok"} — ${cases.length} view tabs × ${targets.join(", ")}`);
process.exit(failed ? 1 : 0);
