// Assemble dist/playground/ : the in-browser MoonBit compiler payload for the
// tutuca-mb playground. Collects the vendored compiler, the core bundle .mi
// (buildPackage stdMiFiles), every project/dep .mi (import interfaces), the
// ordered .core link closure, and the mount-host core, plus a manifest telling
// the shell how to drive buildPackage + linkCore. Also copies the web shell.
//
// Run: node playground/build/assemble.mjs  (assembles js + wasm-gc by default;
// JS_ONLY=1 for js only). It runs the required `moon build` steps itself, so no
// manual pre-build is needed.
import { writeFileSync, mkdirSync, rmSync, readdirSync, statSync, cpSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { build as esbuild } from "esbuild";
import {
  ensureCompiler,
  installedToolchain,
  resolveWorkerForBuild,
  vendoredWorker,
  TOOLCHAIN,
} from "./fetch-compiler.mjs";
import { copyScoped } from "../../scripts/scope-bundle.mjs";
import { DIRECT } from "./direct-packages.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const MOON_HOME = process.env.MOON_HOME || join(process.env.HOME, ".moon");
const OUT = join(REPO, "dist/playground");
const WEB = join(REPO, "playground/web");

// The payload is a PAIR: .mi/.core bundles emitted by the installed moonc, read
// by the js_of_ocaml moonc inside moonc-web.cjs. When the two come from
// different builds the mismatch is silent here and surfaces in the browser as
// nonsense — typically `[E4018] Type X does not implement trait ...Fields`,
// because a stale reader can't see the impls a newer writer emitted. So check
// it at the only moment we still know both halves.
//
// The pin in toolchain.json is the FAST PATH, not the rule. The rule is that
// the worker must be built from the installed moonc, and the pin stands in for
// it because there is no exact-hash selector on npm. When the two disagree —
// which is what CI does every time the toolchain moves, since
// cli.moonbitlang.com serves `latest` and nothing else — the pin being stale
// is not itself a reason to fail: look for a published worker that satisfies
// the actual rule, and fail only if there is none. What used to happen instead
// was a red build on every toolchain bump, with the site frozen at whatever
// commit last matched.
function assertToolchain() {
  const installed = installedToolchain(REPO);
  const pinned = {
    version: TOOLCHAIN.mooncWorker,
    build: TOOLCHAIN.mooncBuild,
  };
  if (installed.moonc && installed.moonc === TOOLCHAIN.moonc) return pinned;

  const stale =
    `toolchain moved: playground/build/toolchain.json pins moonc ${TOOLCHAIN.moonc} ` +
    `(paired with @moonbit/moonc-worker@${TOOLCHAIN.mooncWorker}), and the installed toolchain reports:\n` +
    `${installed.raw}`;

  if (!installed.build) {
    throw new Error(
      stale +
        `\n\`moon version --all\` did not name a moonc build to match a worker against.`,
    );
  }

  // Already holding the right blob from an earlier run: nothing to fetch, and
  // nothing to say beyond the bump.
  const have = vendoredWorker();
  if (have && have.endsWith(`+${installed.build}`)) {
    console.warn(`${stale}\nusing the vendored @moonbit/moonc-worker@${have}`);
    console.warn(bumpHint(have.split("+")[0], installed));
    return { version: have.split("+")[0], build: installed.build };
  }

  console.warn(`${stale}\nlooking for a worker built from ${installed.build} ...`);
  const found = resolveWorkerForBuild(installed.build, installed.moon);
  if (!found) {
    throw new Error(
      stale +
        `\nand npm publishes no @moonbit/moonc-worker built from ${installed.build}.\n` +
        `The payload bakes the INSTALLED toolchain's core bundles, so a mismatched in-browser\n` +
        `moonc fails to link user code. Install the moonc the pin names, or wait for the\n` +
        `worker for this one to be published.\n` +
        `Set TUTUCA_ALLOW_TOOLCHAIN_MISMATCH=1 to assemble anyway (the payload will not work).`,
    );
  }
  console.warn(bumpHint(found, installed));
  return { version: found, build: installed.build };
}

/// The edit that makes today's self-heal tomorrow's fast path. Printed rather
/// than applied: a build step that rewrites a pinned file leaves every CI run
/// with a dirty tree and no one deciding anything.
function bumpHint(worker, installed) {
  return (
    `\nto make this the pin, set playground/build/toolchain.json to:\n` +
    `  "mooncWorker": "${worker}",\n` +
    `  "moonc": "${installed.moonc}",\n` +
    `  "mooncBuild": "${installed.build}",\n` +
    `  "moon": "${installed.moon}"\n`
  );
}

// What the payload will carry: the pin when it holds, the worker the guard
// found when it does not.
let worker = { version: TOOLCHAIN.mooncWorker, build: TOOLCHAIN.mooncBuild };
try {
  worker = assertToolchain();
} catch (e) {
  if (process.env.TUTUCA_ALLOW_TOOLCHAIN_MISMATCH) {
    console.warn("WARNING: " + e.message);
  } else throw e;
}

// The compiler blob is gitignored; fetch the pinned one if a fresh clone
// hasn't got it yet (see playground/build/fetch-compiler.mjs). AFTER the guard
// above, which is what leaves the right blob in place when the pin is the
// stale half — fetching first would download one worker to replace it with
// another.
const WORKER = ensureCompiler(worker);

// The packages a user may import directly. In direct-packages.mjs because
// `scripts/check-playground-examples.mjs` needs the same list to write the
// `moon.pkg` it checks an example against — see the note there.

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
  const lib = walk(buildDir(t), ".mi").filter(([r]) => !/_test|\/test\//.test(r) && !r.includes("/demo/"));
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

// The wasm-gc import contract, from the package that DECLARES it. runtime.js
// imports `./app-loader.mjs` for the jscore/tdom namespaces rather than keeping
// a second copy — the copy went stale once already (`tdom.dropped_files`) and
// every wasm-gc preview LinkError'd. Same name and same source as the copies
// `dev/tasks.mbt` puts beside the counter-wasm and storybook pages.
cpSync(join(REPO, "app/wasm/loader.mjs"), join(OUT, "app-loader.mjs"));

// The view generator, compiled to js: the View tab needs it in the BROWSER
// (it turns view HTML into MoonBit source, which then feeds the in-browser
// compiler). It ships as an ordinary classic script that publishes
// globalThis.__tutucaViewgen on load — wrapped in a scope of its own, because
// moonc's js output declares its symbols at top level and the landing site
// loads a second moonc bundle (site/tutucard.js). See scripts/scope-bundle.mjs.
console.log("building viewgen (js) ...");
execSync("moon build --target js playground/viewgen_js", { cwd: REPO, stdio: "inherit" });
copyScoped(
  join(buildDir("js"), "playground/viewgen_js/viewgen_js.js"),
  join(OUT, "viewgen.js"),
);

// The margaui class compiler, compiled to wasm-gc: previews need it in the
// BROWSER to turn a mounted app's class set into CSS (marianoguerra/tailwindcss
// + the embedded margaui bundle). Shipped as wasm-gc + wasm-opt -Oz — ~3x
// smaller than the js build (~0.47 MB vs ~1.5 MB). runtime.js instantiates it
// and calls its `compile(classesJson) -> css` export.
console.log("building margaui (wasm-gc, release) ...");
execSync("moon build --target wasm-gc --release playground/margaui_wasm", { cwd: REPO, stdio: "inherit" });
const margauiWasm = join(OUT, "margaui.wasm");
cpSync(
  join(REPO, "_build/wasm-gc/release/build/playground/margaui_wasm/margaui_wasm.wasm"),
  margauiWasm,
);
console.log("optimizing margaui.wasm (wasm-opt -Oz) ...");
execSync(
  `moon-wasm-opt --all-features --disable-custom-descriptors -Oz "${margauiWasm}" -o "${margauiWasm}"`,
  { cwd: REPO, stdio: "inherit" },
);

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

// The pin travels WITH the payload, not just in the repo: once these bundles
// are served from somewhere else (a package, a CDN) the toolchain.json that
// produced them is out of reach, and `mooncWorker` is what the worker checks a
// consumer-supplied compiler against (compiler.worker.js assertCompilerPairing).
const manifest = {
  toolchain: TOOLCHAIN.moonc,
  mooncBuild: TOOLCHAIN.mooncBuild,
  moon: TOOLCHAIN.moon,
  mooncWorker: TOOLCHAIN.mooncWorker,
  targets: {},
};
// By default assemble BOTH backends so the shipped playground offers a working
// wasm-gc toggle (see docs/playground-wasm.md for what the two backends do
// differently). Set JS_ONLY=1 to assemble the js backend only.
const TARGETS = process.env.JS_ONLY
  ? [["js", "demo/counter", "playground/host"]]
  : [["js", "demo/counter", "playground/host"], ["wasm-gc", "demo/counter_wasm", "playground/host_wasm"]];
for (const [t, demo, hostPkg] of TARGETS) {
  // Build the moon artifacts this target needs (project + its mount host) so a
  // bare `node assemble.mjs` is self-contained — no manual pre-build step.
  console.log("building moon artifacts for target", t, "...");
  execSync(`moon build --target ${t}`, { cwd: REPO, stdio: "inherit" });
  execSync(`moon build --target ${t} ${hostPkg}`, { cwd: REPO, stdio: "inherit" });
  // The module-ROOT package (the @tutuca facade, see DIRECT above) is not in
  // any build closure — nothing imports it and it has no main — so a bare
  // `moon build` never emits its .mi and @tutuca silently fails to resolve in
  // the browser. Build it by path.
  execSync(`moon build --target ${t} .`, { cwd: REPO, stdio: "inherit" });
  console.log("assembling target", t, "...");
  manifest.targets[t] = assembleTarget(t, demo);
}
writeFileSync(join(OUT, "manifest.json"), JSON.stringify(manifest, null, 1));
const m = manifest.targets.js;
console.log(`done -> ${OUT}\n  js: ${m.std.length} std .mi, ${m.lib.length} lib .mi, ${m.linkOrder.length} cores`);
