#!/usr/bin/env node
// Build this gallery into ./dist:
//
//   moon build --target wasm-gc --release page   the page
//   moon-wasm-opt -Oz                            shrink it
//   copy the loader out of .mooncakes            the JS a wasm-gc page needs
//
// Then: tutuca storybook dist    (or any static server over dist/)
//
// A plain Node script on purpose: `moon` and `node` are all it needs, and it
// reaches nothing outside this directory.
//
// Prereqs: moon (brings moon-wasm-opt), Node >= 20, and network on first run.
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "dist");

const step = (msg) => console.log(`\n\x1b[1m→ ${msg}\x1b[0m`);
const run = (prog, args, cwd = here) =>
  execFileSync(prog, args, { stdio: "inherit", cwd });

function tryRun(prog, args, cwd = here) {
  try {
    execFileSync(prog, args, { stdio: "inherit", cwd });
    return true;
  } catch (err) {
    if (err.code === "ENOENT") return false;
    throw err;
  }
}

// --- 1. the page ----------------------------------------------------------

step("moon build --target wasm-gc --release page");
run("moon", ["build", "--target", "wasm-gc", "--release", "page"]);

const pageWasm = join(here, "_build/wasm-gc/release/build/page/page.wasm");
if (!existsSync(pageWasm)) {
  console.error(`build: expected ${pageWasm} — did the package name change?`);
  process.exit(1);
}

// --- 2. find the installed tutuca -----------------------------------------

// A wasm-gc module cannot reach the DOM, so the JavaScript that gives it one
// comes down with the package and has to land beside the page. Find it where
// `moon` put it. Walking up covers a dependency hoisted to a parent module's
// .mooncakes; the `src/` variant covers modules published with a source root.
function findTutuca() {
  const probe = "app/wasm/loader.mjs";
  let dir = here;
  for (;;) {
    for (const rel of ["", "src/"]) {
      const root = join(dir, ".mooncakes/marianoguerra/tutuca", rel);
      if (existsSync(join(root, probe))) return root;
    }
    const up = dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}

const tutuca = findTutuca();
if (!tutuca) {
  console.error(
    "build: could not find marianoguerra/tutuca in .mooncakes.\n" +
      "  A stale local index resolves an older release that has no storybook\n" +
      "  packages. Run:\n\n    moon update && node build.mjs\n",
  );
  process.exit(1);
}
step(`using ${tutuca}`);

// --- 3. assemble dist ------------------------------------------------------

mkdirSync(dist, { recursive: true });

step("assembling dist/");
copyFileSync(pageWasm, join(dist, "page.wasm"));

// -Oz on the release wasm: roughly 4x smaller, and it is the same module.
// moon-wasm-opt ships with the moon toolchain, so it is there if moon is; bare
// `wasm-opt` is the fallback for a PATH with binaryen but not moon's copy.
// Neither is required — an unoptimized page works, it is just fat.
const optArgs = [
  "--all-features",
  "--disable-custom-descriptors",
  "-Oz",
  join(dist, "page.wasm"),
  "-o",
  join(dist, "page.wasm"),
];
if (!tryRun("moon-wasm-opt", optArgs) && !tryRun("wasm-opt", optArgs)) {
  console.warn(
    "  ! neither moon-wasm-opt nor wasm-opt found — shipping the unoptimized wasm",
  );
}

copyFileSync(join(here, "index.html"), join(dist, "index.html"));
copyFileSync(join(tutuca, "app/wasm/loader.mjs"), join(dist, "app-loader.mjs"));

// The Trace tab's file service. Rewritten rather than copied: it imports the
// app loader by the path the two have inside the package, and in dist/ they
// land flat beside each other.
writeFileSync(
  join(dist, "files-loader.mjs"),
  readFileSync(join(tutuca, "files/wasm/loader.mjs"), "utf8").replace(
    "../../app/wasm/loader.mjs",
    "./app-loader.mjs",
  ),
);

// The copy list is not the check. Reading what landed is: resolve every
// relative specifier — static AND dynamic — in the JS now sitting in dist/, and
// fail if one of them is not there. That turns "the copy list is wrong" into a
// build error instead of a 404 a reader finds by clicking.
const SPECIFIER = /(?:\bfrom\s*|\bimport\s*\(\s*)["'](\.[^"']*)["']/g;
const missing = [];
const scan = ["index.html", "app-loader.mjs", "files-loader.mjs"];
for (const file of scan.filter((f) => existsSync(join(dist, f)))) {
  const src = readFileSync(join(dist, file), "utf8");
  for (const [, spec] of src.matchAll(SPECIFIER)) {
    const target = join(dist, dirname(file), spec);
    if (!existsSync(target)) {
      missing.push(`  ${file} imports "${spec}" — not in dist/`);
    }
  }
}
if (missing.length > 0) {
  console.error("build: dist/ is missing modules its own JS imports:");
  console.error(missing.join("\n"));
  process.exit(1);
}

console.log(
  "\n\x1b[1m✓ dist/ is ready\x1b[0m\n\n" +
    "  tutuca storybook dist            # or any static server over dist/\n",
);
