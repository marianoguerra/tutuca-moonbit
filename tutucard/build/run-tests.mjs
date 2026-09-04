// Every scene every shipped card declares, driven.
//
// `check-examples.mjs` is the gate that says a card LOADS: it checks, compiles
// and instantiates, which between them prove the bytes are right and the host
// will take them. None of that presses a button. A card whose `inc` handler
// adds two passes all three.
//
// This is the fourth gate. It mounts each card on the in-memory DOM through
// the same bundle the page uses, runs the steps its
// `<script type="tutuca/test">` block names, and reports what disagreed. It
// runs HEADLESS — no browser, no server, no MoonBit toolchain — which is what
// makes it a thing CI runs and a thing an agent that generated a card can
// shell out to.
//
// A card with no test block is not a failure. Most of the shipped cards teach
// one directive apiece and have nothing to drive; the count of how many
// declare scenes is printed instead, so it is visible when it stops growing.

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
    `run-tests: ${bundlePath} is missing — run the tutucard-playground task first`,
  );
  process.exit(1);
}
(0, eval)(bundle);

if (!globalThis.__tutucard) {
  console.error("run-tests: the bundle did not install globalThis.__tutucard");
  process.exit(1);
}

const { EXAMPLES } = await import(pathToFileURL(join(OUT, "examples.js")).href);
const { driveCard } = await import(
  pathToFileURL(join(OUT, "card.js")).href
);

// The same two sets `check-examples.mjs` reads, and for the same reason: the
// starter cards are JS strings in a file no MoonBit test can reach, and the
// landing site's are `.html` files in no moon package.
const SITE_CARDS = join(REPO, "playground", "site", "cards");
const CARD_EXAMPLES = join(REPO, "tutucard", "examples");
// The universal demo's layout kit. It is an ordinary card compiled by the
// ordinary compiler — that is the demo's whole claim — so it is driven by the
// ordinary gate rather than by something of its own.
const DEMO_CARDS = join(REPO, "demo", "universal", "std");
const htmlIn = (dir, label) =>
  readdirSync(dir)
    .filter((f) => f.endsWith(".html"))
    .map((f) => ({
      name: `${label}/${f}`,
      source: readFileSync(join(dir, f), "utf8"),
    }));

const cards = [
  ...EXAMPLES.map((e) => ({ name: e.name, source: e.source })),
  ...htmlIn(SITE_CARDS, "site/cards"),
  ...htmlIn(CARD_EXAMPLES, "examples"),
  ...htmlIn(DEMO_CARDS, "universal"),
];

let failed = 0;
let withScenes = 0;
let scenes = 0;

for (const card of cards) {
  // Cheap and exact: a card with no block has no scenes to drive, and
  // compiling it to find that out would cost a wasm module per card.
  if (!card.source.includes('type="tutuca/test"')) continue;

  const report = await driveCard(card.source, "Card");
  if (report.ok === false && report.scenes === undefined) {
    console.error(`✗ ${card.name}: ${report.error ?? "did not compile"}`);
    failed++;
    continue;
  }
  withScenes++;
  for (const [name, s] of Object.entries(report.scenes)) {
    scenes++;
    if (s.ok) {
      console.log(`ok      ${card.name} — ${name}`);
      continue;
    }
    failed++;
    if (s.error) {
      console.error(`✗ ${card.name} — ${name}: ${s.error}`);
      continue;
    }
    console.error(`✗ ${card.name} — ${name}`);
    for (const step of s.steps) {
      if (!step.ok) console.error(`          step ${step.at}: ${step.why}`);
    }
    // The rendered DOM, once, for whoever has to work out why. It is the
    // thing you would have opened the page to look at.
    console.error(`          html: ${s.html}`);
  }
}

if (failed > 0) {
  console.error(`\n${failed} scene(s) failed`);
  process.exit(1);
}
console.log(
  `\n${scenes}/${scenes} scenes pass, across ${withScenes} of ${cards.length} cards`,
);
