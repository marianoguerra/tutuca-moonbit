// Assemble dist/playground/ : the in-browser MoonBit compiler payload for the
// tutuca-mb playground. Collects the vendored compiler, the core bundle .mi
// (buildPackage stdMiFiles), every project/dep .mi (import interfaces), the
// ordered .core link closure, and the mount-host core, plus a manifest telling
// the shell how to drive buildPackage + linkCore. Also copies the web shell.
//
// Prereqs: `moon build --target js` and `moon build --target js playground/host`
// have run (so _build/js has the artifacts). Run: node playground/build/assemble.mjs
import { writeFileSync, mkdirSync, rmSync, readdirSync, statSync, cpSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { build as esbuild } from "esbuild";
import { ensureCompiler } from "./fetch-compiler.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const MOON_HOME = process.env.MOON_HOME || join(process.env.HOME, ".moon");
const OUT = join(REPO, "dist/playground");
// The compiler blob is gitignored; fetch the pinned one if a fresh clone
// hasn't got it yet (see playground/build/fetch-compiler.mjs).
const WORKER = ensureCompiler();
const WEB = join(REPO, "playground/web");
const TOOLCHAIN = "v0.10.3+16975d007"; // must match the vendored/fetched moonc-web.cjs (see fetch-compiler.mjs)

// packages a user may import directly (distinct aliases — no browser/browser clash)
const DIRECT = [
  ["host", "playground/host/host"],
  ["component", "component/component"],
  ["tutuca", "tutuca"],
  ["anode", "anode/anode"],
  ["app", "app/app"],
  ["render", "render/render"],
  ["vdom", "vdom/vdom"],
  ["transactor", "transactor/transactor"],
];

const bundleDir = (t) => join(MOON_HOME, `lib/core/_build/${t}/release/bundle`);
const buildDir = (t) => join(REPO, `_build/${t}/debug/build`);

function walk(dir, ext, base = dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, ext, base, out);
    else if (e.endsWith(ext)) out.push([p.slice(base.length + 1), p]);
  }
  return out;
}

function resolveCore(t, tok) {
  return tok.replace("$MOON_HOME", MOON_HOME)
    .replace(new RegExp(`^\\./_build/${t}/debug/build/`), buildDir(t) + "/");
}

// ordered core link closure from `moon build --dry-run <demo>`, minus the demo's
// own module packages (replaced at runtime by the host + user cores).
function linkClosure(t, demoPkg) {
  const dry = execSync(`moon build --target ${t} --dry-run ${demoPkg}`, { cwd: REPO, encoding: "utf8" });
  const line = dry.split("\n").find((l) => l.includes("link-core"));
  if (!line) throw new Error(`no link-core in dry-run for ${t}`);
  return [...line.matchAll(/'?([^ ']+\.core)'?/g)].map((m) => m[1])
    .filter((tk) => !/counterlib|demo\/counter/.test(tk))
    .map((tk) => resolveCore(t, tk));
}

function assembleTarget(t, demoPkg) {
  const fsdir = join(OUT, "fs", t);
  const std = walk(bundleDir(t), ".mi");
  for (const [rel, abs] of std) { const d = join(fsdir, "std", rel); mkdirSync(dirname(d), { recursive: true }); cpSync(abs, d); }
  // The value+path core lives in the `core/` package (marianoguerra/tutuca/core),
  // but user code imports it as @tutuca (the alias the library's own moon.pkg
  // files use). buildPackage derives a direct import's alias from the last path
  // segment of its .mi name, so expose core's .mi as `tutuca.mi` (-> @tutuca) and
  // drop the now-empty module-root package's own tutuca.mi. Mirrors the
  // `-i core/core.mi:tutuca` that moon emits for every core importer.
  const lib = walk(buildDir(t), ".mi")
    .filter(([r]) => !/_test|\/test\//.test(r) && !r.includes("/demo/"))
    .filter(([r]) => r !== "tutuca.mi")
    .map(([r, abs]) => (r === "core/core.mi" ? ["tutuca.mi", abs] : [r, abs]));
  for (const [rel, abs] of lib) { const d = join(fsdir, "lib", rel); mkdirSync(dirname(d), { recursive: true }); cpSync(abs, d); }
  const closure = linkClosure(t, demoPkg);
  const coreRel = [];
  for (const abs of closure) {
    const rel = "cores/" + String(coreRel.length).padStart(3, "0") + "_" + abs.split("/").slice(-2).join("_");
    const d = join(fsdir, rel); mkdirSync(dirname(d), { recursive: true }); cpSync(abs, d);
    coreRel.push(rel);
  }
  const host = t === "wasm-gc"
    ? { core: "playground/host_wasm/host_wasm.core", mi: "playground/host_wasm/host_wasm" }
    : { core: "playground/host/host.core", mi: "playground/host/host" };
  const hostRel = "cores/" + String(coreRel.length).padStart(3, "0") + "_playground_host.core";
  cpSync(join(buildDir(t), host.core), join(fsdir, hostRel));
  coreRel.push(hostRel);
  const directList = DIRECT.map(([, sub]) => sub === "playground/host/host" ? host.mi : sub);
  const directMi = new Set(directList.map((sub) => `lib/${sub}.mi`));
  // wasm-gc user modules name @core.Any (the on_event signature), so mizchi's
  // js/core must be a DIRECT import — its alias is the last path segment, `core`.
  if (t === "wasm-gc") directMi.add("lib/.mooncakes/mizchi/js/core/core.mi");
  return {
    target: t,
    direct: [...directMi].filter((p) => existsSync(join(fsdir, p))),
    std: std.map(([rel]) => `std/${rel}`),
    lib: lib.map(([rel]) => `lib/${rel}`),
    linkOrder: coreRel,
    userPkg: "user/app",
  };
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
cpSync(WORKER, join(OUT, "moonc-web.cjs"));
for (const f of readdirSync(WEB)) cpSync(join(WEB, f), join(OUT, f));

// Bundle the shared CodeMirror editor to a single ESM file both the standalone
// shell (driver.js) and the embeddable element (site/embed.js) import.
await esbuild({
  entryPoints: [join(REPO, "playground/editor/editor.js")],
  outfile: join(OUT, "editor.bundle.js"),
  bundle: true,
  format: "esm",
  minify: true,
  target: "es2020",
  logLevel: "warning",
});
console.log("bundled editor.bundle.js");

const manifest = { toolchain: TOOLCHAIN, targets: {} };
const TARGETS = process.env.WASMGC ? [["js", "demo/counter"], ["wasm-gc", "demo/counter_wasm"]] : [["js", "demo/counter"]];
for (const [t, demo] of TARGETS) {
  console.log("assembling target", t, "...");
  manifest.targets[t] = assembleTarget(t, demo);
}
writeFileSync(join(OUT, "manifest.json"), JSON.stringify(manifest, null, 1));
const m = manifest.targets.js;
console.log(`done -> ${OUT}\n  js: ${m.std.length} std .mi, ${m.lib.length} lib .mi, ${m.linkOrder.length} cores`);
