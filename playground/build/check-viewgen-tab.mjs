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
// Covered: the standalone playground's starter example (starter.js) and every
// landing-site example pair (playground/site/examples/<name>.{mbt,html}) —
// those are what dist/index.html compiles in a visitor's browser.
//
// Run after `node playground/build/assemble.mjs`:
//   node playground/build/check-viewgen-tab.mjs

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
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

const starterSrc = readFileSync(join(OUT, "starter.js"), "utf8");
const window = {};
new Function("window", starterSrc)(window);
const starter = window.EXAMPLES["Counter"];
if (!starter || !starter.view) throw new Error("starter has no view-tab example");
cases.push({ label: "starter:Counter", code: starter.code, html: starter.view });

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

// --- the in-browser compiler, as the worker drives it -----------------------
globalThis.process = process;
const moonc = (await import(join(OUT, "moonc-web.cjs"))).default;
const manifest = JSON.parse(readFileSync(join(OUT, "manifest.json"), "utf8"));
const m = manifest.targets.js;
const base = join(OUT, "fs", "js");
const load = (list) => list.map((p) => [p, new Uint8Array(readFileSync(join(base, p)))]);
const directSet = new Set(m.direct);
const lib = load(m.lib);
const std = load(m.std);
const cores = m.linkOrder.map((p) => new Uint8Array(readFileSync(join(base, p))));

const BOOT = `fn main {
  @host.mount(build(), "app")
}
`;

// moonc's diagnostics accumulate across buildPackage calls in one process, so
// each case reports only what its own compile added.
let seenDiagnostics = 0;
let failed = 0;
for (const c of cases) {
  const gen = generate(c.html);
  process.stdout.write(
    `${c.label}: generated ${gen.name} (${gen.module.length} B types + ${gen.ir.length} B tree) … `,
  );

  const bp = moonc.buildPackage({
    mbtFiles: [
      ["main.mbt", c.code],
      ["_boot.mbt", BOOT],
      ["_views.mbt", gen.module],
      ["_views_ir.mbt", gen.ir],
    ],
    miFiles: lib.filter(([p]) => directSet.has(p)),
    indirectImportMiFiles: lib.filter(([p]) => !directSet.has(p)),
    stdMiFiles: std,
    target: "js",
    pkg: m.userPkg,
    pkgSources: [m.userPkg + ":."],
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
    continue;
  }

  // Link too: a package can type-check and still fail to link (a missing core
  // in the closure), and the page's next step after compile is exactly this.
  const lk = moonc.linkCore({
    coreFiles: [...cores, bp.core],
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
  console.log(`ok — compiled + linked (${js.length} B)`);
  if (diagnostics.length) {
    console.log(diagnostics.map((d) => "  " + d).join("\n"));
  }
}

console.log(`\n${cases.length - failed}/${cases.length} view tabs compile + link`);
process.exit(failed ? 1 : 0);
