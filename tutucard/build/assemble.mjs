// Assemble dist/tutucard/.
//
// Nine files copied and two built. That is the whole build, and the brevity is
// still the point: the other playground assembles a vendored 5.5 MB compiler, a
// per-target `.mi`/`.core` closure and a manifest telling the shell how to
// drive `buildPackage`/`linkCore`, because it compiles MoonBit in the browser.
//
// A card is parsed and mounted, so what ships is the runtime and the page — AND
// a compiler, which is new. `tutucard/wasm` turns the same card into a
// `tutuca:component@0.12.0` core wasm module, and it is a MoonBit library in
// this bundle rather than a payload fetched beside it: `marianoguerra/wax` plus
// the Wax standard library it vendors, which is why `abi.mjs` and
// `card-wasm.js` are copied too.
//
// The two built things are the compilers a card can ask for, and neither is
// new: `margaui.wasm` is the wasm-gc build of `@css.compile_margaui` the other
// playground ships — what turns a card's `class="btn btn-primary"` into a
// button — and `editor.bundle.js` is the shared CodeMirror the two playgrounds
// already edit MoonBit and view files in. Both are fetched lazily by the page:
// margaui on the first mount that publishes a class name, the editor after the
// first card is mounted and typeable — so neither is ever in front of the
// page, and an `<mb-card>` without `codemirror` never asks for the editor at
// all.

import { execSync } from "node:child_process";
import { build as esbuild } from "esbuild";
import { cpSync, mkdirSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { copyScoped } from "../../scripts/scope-bundle.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const WEB = join(HERE, "..", "web");
const OUT = join(REPO, "dist", "tutucard");

/** The web files this page and its embeddable element are made of. */
const WEB_FILES = [
  "index.html",
  "shell.js",
  "shell.css",
  "examples.js",
  "regions.js",
  // The embeddable element ships beside the playground rather than only in
  // the landing site's folder: a host that has this directory has the
  // runtime, and `<mb-card>` needs nothing else.
  "card-embed.js",
  // …except the class compiler, which both the shell and the element import.
  "margaui.js",
  // The compiler's half of the page: the guest bridge over `abi.mjs` and the
  // `.tutuca.tar.gz` packer. Imported lazily by `shell.js` — a reader who
  // never downloads a bundle never fetches it.
  "card-wasm.js",
];

/**
 * The host's own canonical ABI, COPIED rather than reimplemented.
 *
 * `card-wasm.js` instantiates a compiled card through it, which is what makes
 * "this page produced a real `tutuca:component` guest" a claim about the
 * artifact rather than about the playground. If this file ever needs editing to
 * make the page work, the generator is wrong and not this copy.
 */
function copyAbi(out) {
  cpSync(join(REPO, "dyncomp", "host", "wasm", "abi.mjs"), join(out, "abi.mjs"));
}

function build() {
  console.log("building tutucard/playground (js) ...");
  execSync("moon build --target js --release tutucard/playground", {
    cwd: REPO,
    stdio: "inherit",
  });
}

/**
 * Build margaui.wasm into `out`.
 *
 * The landing site does not run this a second time: `assemble-site.mjs` copies
 * the artifact out of here, the same way it copies the runtime, because an
 * `<mb-card margaui>` resolves the wasm against the module that fetches it and
 * the site keeps its own copy of `margaui.js`.
 *
 * wasm-opt -Oz is what makes this ~0.47 MB rather than ~1.3 MB, so it is not
 * optional — but it is a separate binary, and a build that cannot find it
 * should say which one rather than fail with a shell error.
 */
function buildMargaui(out) {
  console.log("building margaui (wasm-gc, release) ...");
  execSync("moon build --target wasm-gc --release playground/margaui_wasm", {
    cwd: REPO,
    stdio: "inherit",
  });
  cpSync(
    join(
      REPO,
      "_build/wasm-gc/release/build/playground/margaui_wasm/margaui_wasm.wasm",
    ),
    out,
  );
  console.log("optimizing margaui.wasm (wasm-opt -Oz) ...");
  try {
    execSync(
      `moon-wasm-opt --all-features --disable-custom-descriptors -Oz "${out}" -o "${out}"`,
      { cwd: REPO, stdio: "inherit" },
    );
  } catch {
    throw new Error(
      "moon-wasm-opt failed or is not on PATH — it ships with the MoonBit toolchain (~/.moon/bin)",
    );
  }
  return statSync(out).size;
}

/**
 * Bundle the shared CodeMirror editor into `out`.
 *
 * Bundled here rather than copied from `dist/playground/`, which has an
 * identical file: this directory is meant to stand on its own — a host that
 * has it has everything `<mb-card>` needs — and depending on the compiler
 * payload's build for a text editor would undo that for 330 KB.
 *
 * Two callers now: the playground page upgrades its own textareas to it (the
 * default, `?editor=plain` opts out) and an `<mb-card codemirror>` upgrades
 * its own.
 */
async function buildEditor(out) {
  console.log("bundling editor (esbuild, esm) ...");
  await esbuild({
    entryPoints: [join(REPO, "playground/editor/editor.js")],
    outfile: out,
    bundle: true,
    format: "esm",
    minify: true,
    target: "es2020",
    logLevel: "warning",
  });
  return statSync(out).size;
}

async function assemble() {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  for (const name of WEB_FILES) {
    cpSync(join(WEB, name), join(OUT, name));
  }
  copyAbi(OUT);
  const bundle = join(
    REPO,
    "_build",
    "js",
    "release",
    "build",
    "tutucard",
    "playground",
    "playground.js",
  );
  // Scoped rather than copied: the landing page loads this bundle AND the
  // playground's viewgen.js, and two moonc bundles sharing the global scope
  // collide on every core symbol. See scripts/scope-bundle.mjs.
  copyScoped(bundle, join(OUT, "tutucard.js"));
  const kb = (statSync(join(OUT, "tutucard.js")).size / 1024).toFixed(0);
  const css = (buildMargaui(join(OUT, "margaui.wasm")) / 1024).toFixed(0);
  const ed = (
    (await buildEditor(join(OUT, "editor.bundle.js"))) / 1024
  ).toFixed(0);
  console.log(`assembled ${OUT}`);
  // Printed every time, because it is the number this page exists to keep
  // small: the other playground's compiler payload alone is ~5.5 MB.
  console.log(`  runtime: ${kb} KB (runtime + card compiler; no worker, no payload)`);
  console.log(`  margaui: ${css} KB (fetched only by a card with classes)`);
  console.log(`  editor:  ${ed} KB (fetched after first mount; ?editor=plain skips it)`);
}

build();
await assemble();
