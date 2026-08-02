#!/usr/bin/env node
// Build the dyncomp-dice example end to end, into ./dist:
//
//   moon build --target wasm-gc --release page   the host page
//   moon-wasm-opt -Oz                            shrink it
//   copy two loaders out of .mooncakes           the JS a wasm-gc page needs
//   node dice/build.mjs && dice/pack.mjs         the local guest -> one archive
//
// Then: python3 -m http.server 8099 -d dist
//
// This is deliberately a plain Node script rather than a task in the tutuca
// repo's runner. A consumer has `moon` and `node` and nothing else of ours —
// `cmd/dev`, the justfile and the storybook are all excluded from the published
// package — so anything this script needed from upstairs would be a step a real
// user could not take. There is no `..` anywhere below.
//
// Prereqs: moon 0.10.x (brings moon-wasm-opt), wasm-tools 1.244.x, Node >= 20,
// and network on the first run. See README.md.
//
//   node build.mjs                 everything
//   node build.mjs --skip-guest    page only (the fast inner loop)
//   node build.mjs --skip-npm      assume dice/node_modules is already there
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "dist");
const argv = new Set(process.argv.slice(2));
const skipGuest = argv.has("--skip-guest");
const skipNpm = argv.has("--skip-npm");

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

const pageWasm = join(
  here,
  "_build/wasm-gc/release/build/page/page.wasm",
);
if (!existsSync(pageWasm)) {
  console.error(`build: expected ${pageWasm} — did the package name change?`);
  process.exit(1);
}

// --- 2. find the installed tutuca -----------------------------------------

// A wasm-gc module cannot reach the DOM, so two JavaScript files come down with
// the package and have to land beside the page. Find them where `moon` put
// them. Walking up covers the case where the dependency was hoisted to a parent
// module's .mooncakes; the `src/` variant covers modules published with a
// source root (tutuca is not one, but its siblings are, and this check costs
// nothing).
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
      "  The dynamic-component host and its two JS loaders only exist from\n" +
      "  version 0.9.5 onward, and a stale local index may resolve older,\n" +
      "  has none of it. Run:\n\n" +
      "    moon update && node build.mjs\n",
  );
  process.exit(1);
}
step(`using ${tutuca}`);

// --- 3. assemble dist ------------------------------------------------------

mkdirSync(join(dist, "examples"), { recursive: true });

step("assembling dist/");
copyFileSync(pageWasm, join(dist, "page.wasm"));

// -Oz on the release wasm: roughly 4x smaller, and it is the same module.
// moon-wasm-opt ships with the moon toolchain, so it is there if moon is; the
// bare `wasm-opt` is the fallback for a PATH that has binaryen but not moon's
// copy. Neither is required — an unoptimized page works, it is just fat.
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

copyFileSync(join(here, "page/index.html"), join(dist, "index.html"));
copyFileSync(join(here, "page/loader.mjs"), join(dist, "loader.mjs"));
copyFileSync(
  join(tutuca, "app/wasm/loader.mjs"),
  join(dist, "app-loader.mjs"),
);

// The dyncomp loader imports the app loader by the relative path that is
// correct where the two live inside the package. Here they land flat beside the
// page, so repoint it — the same repointing the tutuca repo's own dist step
// does. Asserting the replacement happened is the whole value of doing it in
// code: a silently-unmatched rewrite produces a broken page from a green build,
// and the failure shows up as a 404 for a directory three levels above the
// server root.
const FROM = "../../../app/wasm/loader.mjs";
const TO = "./app-loader.mjs";
const dyncompLoader = readFileSync(
  join(tutuca, "dyncomp/host/wasm/loader.mjs"),
  "utf8",
);
if (!dyncompLoader.includes(FROM)) {
  console.error(
    `build: ${join(tutuca, "dyncomp/host/wasm/loader.mjs")} no longer imports\n` +
      `  "${FROM}". Its layout changed — update the rewrite in this script.`,
  );
  process.exit(1);
}
writeFileSync(
  join(dist, "dyncomp-loader.mjs"),
  dyncompLoader.replaceAll(FROM, TO),
);

// --- 4. the guest ----------------------------------------------------------

if (skipGuest) {
  console.log("\n  (--skip-guest: dist/examples left as it was)");
} else {
  const guest = join(here, "dice");
  const jco = join(guest, "node_modules/@bytecodealliance/jco");
  if (!existsSync(jco)) {
    if (skipNpm) {
      console.error(
        "build: --skip-npm, but dice/node_modules/@bytecodealliance/jco is missing",
      );
      process.exit(1);
    }
    // Inside dice/, not here: dice/build.mjs resolves jco against its OWN
    // directory, so an npm workspace at this level would break it.
    step("npm install (jco, inside dice/)");
    run("npm", ["install"], guest);
  }

  step("building the dice guest (moon -> component -> ESM)");
  run(process.execPath, [join(guest, "build.mjs")], guest);

  step("packing dice.tutuca.tar.gz");
  run(
    process.execPath,
    [join(guest, "pack.mjs"), "dist/js", resolve(dist, "examples/dice.tutuca.tar.gz")],
    guest,
  );
}

// --- done ------------------------------------------------------------------

console.log(
  "\n\x1b[1mdone.\x1b[0m serve it with:\n\n" +
    "  python3 -m http.server 8099 -d dist\n\n" +
    "then open http://localhost:8099/ in Chrome or Edge (the page needs the\n" +
    "JS String Builtins proposal, which Firefox does not have yet).\n",
);
