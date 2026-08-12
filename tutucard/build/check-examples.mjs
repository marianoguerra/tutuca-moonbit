// Every starter card loads, with no issues.
//
// The one thing that has to keep being true as the language moves, and the one
// nothing else checks: the examples are JavaScript strings in a file no MoonBit
// test can reach, so a card that stopped parsing would be found by whoever
// opened the page. This runs the REAL loader over them — the same
// `globalThis.__tutucard.load` the page calls — in the assembled payload.
//
// It runs headless, so it calls `check` rather than `load` — the same report
// without the half that needs a page. That split is worth having anyway: an
// agent that generated a card, or a build step over a directory of them,
// validates without showing anything.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT = join(REPO, "dist", "tutucard");

const bundlePath = join(OUT, "tutucard.js");
let bundle;
try {
  bundle = readFileSync(bundlePath, "utf8");
} catch {
  console.error(
    `check-examples: ${bundlePath} is missing — run the tutucard-playground task first`,
  );
  process.exit(1);
}

// The bundle is a classic script that installs `globalThis.__tutucard`. Running
// it with indirect eval gives it the global scope it expects.
(0, eval)(bundle);

if (!globalThis.__tutucard) {
  console.error("check-examples: the bundle did not install globalThis.__tutucard");
  process.exit(1);
}

const { EXAMPLES } = await import(
  pathToFileURL(join(OUT, "examples.js")).href
);

let failed = 0;
for (const ex of EXAMPLES) {
  const report = JSON.parse(globalThis.__tutucard.check(ex.source, "Card"));
  if (!report.ok) {
    console.error(`✗ ${ex.name}: ${report.error} (line ${report.line})`);
    failed++;
    continue;
  }
  if (report.issues.length > 0) {
    for (const i of report.issues) {
      console.error(`✗ ${ex.name}: line ${i.line} ${i.code} — ${i.message}`);
    }
    failed++;
    continue;
  }
  console.log(`ok      ${ex.name} (${report.component})`);
}

if (failed > 0) {
  console.error(`\n${failed} starter card(s) do not load`);
  process.exit(1);
}
console.log(`\n${EXAMPLES.length}/${EXAMPLES.length} starter cards load`);
