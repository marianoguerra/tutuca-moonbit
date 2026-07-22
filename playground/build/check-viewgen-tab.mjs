// End-to-end check for the playground's View tab: take the shipped starter
// example, run the SAME view generator the page runs (viewgen.js), and hand
// the result to the SAME in-browser compiler the worker drives — with the
// generated modules as extra files of the user's package, exactly as
// compiler.worker.js does.
//
// This is the piece a headless test cannot otherwise reach: that the module
// `tutuca gen-views` emits actually compiles inside the playground's package,
// where there is no moon.pkg to declare imports and `@tutuca` is the
// module-root facade rather than core/.
//
// Run after `node playground/build/assemble.mjs`:
//   node playground/build/check-viewgen-tab.mjs

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const OUT = join(REPO, "dist/playground");

if (!existsSync(join(OUT, "manifest.json"))) {
  console.error("dist/playground missing — run: node playground/build/assemble.mjs");
  process.exit(1);
}

// --- the view generator, as the page loads it -------------------------------
const genSrc = readFileSync(join(OUT, "viewgen.js"), "utf8");
new Function(genSrc)(); // publishes globalThis.__tutucaViewgen

// --- the starter example, as the page loads it ------------------------------
const starterSrc = readFileSync(join(OUT, "starter.js"), "utf8");
const window = {};
new Function("window", starterSrc)(window);
const example = window.EXAMPLES["Counter (view tab)"];
if (!example || !example.view) throw new Error("starter has no view-tab example");

// The driver reads the component name from a `<!-- name: X -->` comment.
const name = (/<!--\s*name:\s*([A-Za-z]\w*)\s*-->/.exec(example.view) || [, "View"])[1];
const gen = JSON.parse(globalThis.__tutucaViewgen(example.view, name));
if (!gen.ok) throw new Error("generation failed: " + gen.error);
if (!gen.ir) throw new Error("expected a compiled tree for the starter view");
console.log(`generated ${name}: ${gen.module.length} B types + ${gen.ir.length} B tree`);

// --- the in-browser compiler, as the worker drives it -----------------------
globalThis.process = process;
const moonc = (await import(join(OUT, "moonc-web.cjs"))).default;
const manifest = JSON.parse(readFileSync(join(OUT, "manifest.json"), "utf8"));
const m = manifest.targets.js;
const base = join(OUT, "fs", "js");
const load = (list) => list.map((p) => [p, new Uint8Array(readFileSync(join(base, p)))]);
const directSet = new Set(m.direct);
const lib = load(m.lib);

const BOOT = `fn main {
  @host.mount(build(), "app")
}
`;

const bp = moonc.buildPackage({
  mbtFiles: [
    ["main.mbt", example.code],
    ["_boot.mbt", BOOT],
    ["_views.mbt", gen.module],
    ["_views_ir.mbt", gen.ir],
  ],
  miFiles: lib.filter(([p]) => directSet.has(p)),
  indirectImportMiFiles: lib.filter(([p]) => !directSet.has(p)),
  stdMiFiles: load(m.std),
  target: "js",
  pkg: m.userPkg,
  pkgSources: [m.userPkg + ":."],
  isMain: true,
  errorFormat: "human",
  enableValueTracing: false,
  noOpt: false,
});

const errs = (bp.diagnostics || []).filter((d) => /\[E\d+\]|error/i.test(d));
if (!bp.core || errs.length) {
  console.error("FAILED — the generated module does not compile in the playground:\n");
  console.error((bp.diagnostics || []).join("\n\n"));
  process.exit(1);
}
console.log("ok — component + generated view modules compile as one package");

// Link too: a package can type-check and still fail to link (a missing core in
// the closure), and the page's next step after compile is exactly this.
const lk = moonc.linkCore({
  coreFiles: [...m.linkOrder.map((p) => new Uint8Array(readFileSync(join(base, p)))), bp.core],
  main: m.userPkg,
  pkgSources: [m.userPkg + ":."],
  target: "js",
  exportedFunctions: [],
  outputFormat: "wasm",
  testMode: false,
  debug: false,
  noOpt: false,
  sourceMap: false,
  sources: {},
  stopOnMain: false,
});
const js = new TextDecoder().decode(lk.result);
if (!js.includes("function")) throw new Error("linked output does not look like JS");
console.log(`ok — linked to a runnable module (${js.length} B)`);
if ((bp.diagnostics || []).length) {
  console.log("\nwarnings:\n" + bp.diagnostics.join("\n"));
}
