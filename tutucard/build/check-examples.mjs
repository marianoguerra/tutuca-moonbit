// Every card that ships loads, with no issues.
//
// The one thing that has to keep being true as the language moves, and the one
// nothing else checks: the starter cards are JavaScript strings in a file no
// MoonBit test can reach, and the landing site's are `.html` files in no moon
// package, so a card that stopped parsing would be found by whoever opened the
// page. This runs the REAL loader over both sets — the same
// `globalThis.__tutucard.check` and `.compile` the page calls — in the
// assembled payload.
//
// It runs headless, so it calls `check` rather than `load` — the same report
// without the half that needs a page. That split is worth having anyway: an
// agent that generated a card, or a build step over a directory of them,
// validates without showing anything.

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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

// The starter cards, plus the ones the landing page embeds in <mb-card>. Read
// off disk rather than out of the assembled site, so this checks what is in the
// tree whether or not the site has been assembled.
const SITE_CARDS = join(REPO, "playground", "site", "cards");
const cards = [
  ...EXAMPLES.map((e) => ({ name: e.name, source: e.source })),
  ...readdirSync(SITE_CARDS)
    .filter((f) => f.endsWith(".html"))
    .map((f) => ({
      name: `site/cards/${f}`,
      source: readFileSync(join(SITE_CARDS, f), "utf8"),
    })),
];

// The host half of the payload, imported from the assembled folder so this
// runs the same `card.js` the page loads rather than a copy of it.
const { loadGuest } = await import(
  pathToFileURL(join(OUT, "card.js")).href
);

/** The base64 the compiler answers with, as the bytes `loadGuest` takes. */
const bytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

let failed = 0;
for (const ex of cards) {
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
  // …and it COMPILES. Checking used to be the whole gate, because mounting a
  // card meant handing it to an interpreter and a card that checked would run.
  // Mounting is compiling now, so a card that checks and does not compile is a
  // card this page cannot show — which is exactly what this file exists to
  // catch before a reader does.
  const build = JSON.parse(globalThis.__tutucard.compile(ex.source, "Card"));
  if (!build.ok) {
    console.error(`✗ ${ex.name}: does not compile — ${build.error}`);
    failed++;
    continue;
  }
  // A REFUSAL is not a failure: the declaration is left out, the host falls
  // back, and the rest of the card runs. It is worth printing, because a
  // starter card is meant to be exemplary and a refused handler in one is
  // usually a card to rewrite rather than a backend to extend.
  for (const r of build.refusals) {
    console.log(`  note  ${ex.name}: refused ${r.kind} ${r.name} — ${r.reason}`);
  }
  // …and it INSTANTIATES against the host that ships beside it.
  //
  // The third gate, and the one the first two cannot stand in for: a card's
  // import section is decided by the effects it performs, so `intent lex
  // 'loadQuote'` puts `tut.intent` in a module that checks and compiles
  // perfectly — and imports bind BY NAME, so a runtime missing that export
  // throws at instantiation rather than dropping the effect. Which is how step
  // 7 of the tutorial shipped as a card that compiled and would not mount.
  try {
    await loadGuest(bytes(build.wasm), "check");
  } catch (e) {
    console.error(`✗ ${ex.name}: does not instantiate — ${e.message}`);
    failed++;
    continue;
  }
  console.log(
    `ok      ${ex.name} (${report.component}, ${(build.size / 1024).toFixed(1)} KB)`,
  );
}

if (failed > 0) {
  console.error(`\n${failed} card(s) do not load`);
  process.exit(1);
}
console.log(`\n${cards.length}/${cards.length} cards load`);
