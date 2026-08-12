// Assemble dist/tutucard/.
//
// Five files copied and one built. That is the whole build, and the brevity is
// the point: the other playground assembles a vendored compiler, a per-target
// `.mi`/`.core` closure and a manifest telling the shell how to drive
// `buildPackage`/`linkCore`, because it compiles MoonBit in the browser. A card
// is parsed and mounted, so what ships is the runtime and the page.

import { execSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const WEB = join(HERE, "..", "web");
const OUT = join(REPO, "dist", "tutucard");

function build() {
  console.log("building tutucard/playground (js) ...");
  execSync("moon build --target js --release tutucard/playground", {
    cwd: REPO,
    stdio: "inherit",
  });
}

function assemble() {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  for (const name of [
    "index.html",
    "shell.js",
    "shell.css",
    "examples.js",
    "regions.js",
  ]) {
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
  cpSync(bundle, join(OUT, "tutucard.js"));
  const kb = (statSync(join(OUT, "tutucard.js")).size / 1024).toFixed(0);
  console.log(`assembled ${OUT}`);
  // Printed every time, because it is the number this page exists to keep
  // small: the other playground's compiler payload alone is ~5.5 MB.
  console.log(`  runtime: ${kb} KB (no compiler, no worker, no payload)`);
}

build();
assemble();
