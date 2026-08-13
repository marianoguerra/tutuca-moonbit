// Assemble dist/tutucard/.
//
// Seven files copied and two built. That is the whole build, and the brevity is
// the point: the other playground assembles a vendored compiler, a per-target
// `.mi`/`.core` closure and a manifest telling the shell how to drive
// `buildPackage`/`linkCore`, because it compiles MoonBit in the browser. A card
// is parsed and mounted, so what ships is the runtime and the page.
//
// The second built thing is `margaui.wasm`, the CSS class compiler — the same
// wasm-gc build of `@css.compile_margaui` the other playground ships, because
// there is one of it. It is what turns a card's `class="btn btn-primary"` into
// a button; without it the starter cards render as unstyled markup. It is
// fetched lazily by the page, so a card with no classes never pays for it.

import { execSync } from "node:child_process";
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
];

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

function assemble() {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  for (const name of WEB_FILES) {
    cpSync(join(WEB, name), join(OUT, name));
  }
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
  console.log(`assembled ${OUT}`);
  // Printed every time, because it is the number this page exists to keep
  // small: the other playground's compiler payload alone is ~5.5 MB.
  console.log(`  runtime: ${kb} KB (no compiler, no worker, no payload)`);
  console.log(`  margaui: ${css} KB (fetched only by a card with classes)`);
}

build();
assemble();
