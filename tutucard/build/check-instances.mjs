// A card does not grow a table entry per keystroke.
//
// A guest instance is immutable, so every transition that answers a successor
// makes its predecessor garbage — which is every interaction. The host has a
// collector for that (`tgc/host/dynobj.mbt`, `install_gc`) and it was
// handing the doomed handles to a card guest whose `drop_instance` did
// nothing, on the grounds that the table goes with the module. True, and never
// the whole story: a card left open on a page grew forever.
//
// The other half is the row that is simply REMOVED. `.items.deleteAt 0` gives
// the list a successor and the child it dropped was superseded by nothing —
// there is no predecessor/successor pair to notice, only a place it used to
// be. Reachability is what finds that, and the host can answer it because it
// holds the root.
//
// This watches both. The numbers are exact rather than a bound: a card with
// three rows holds four instances — itself and three — whatever it did to get
// there.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT = join(REPO, "dist", "tutucard");

let bundle;
try {
  bundle = readFileSync(join(OUT, "tutucard.js"), "utf8");
} catch {
  console.error("check-instances: run the tutucard-playground task first");
  process.exit(1);
}
(0, eval)(bundle);

const { driveCard } = await import(
  pathToFileURL(join(OUT, "card.js")).href
);
const CARD = readFileSync(
  join(REPO, "tutucard", "wasm", "examples", "Todos.html"),
  "utf8",
);

let failed = 0;
const check = (name, got, want) => {
  if (got === want) {
    console.log(`ok      ${name} (${got})`);
  } else {
    console.error(`✗ ${name}: ${got}, want ${want}`);
    failed++;
  }
};

const add = (t) => [{ type: "input.draft", value: t }, { click: "button.add" }];
const drive = async (steps) => {
  await driveCard(CARD, "Todos", { scenes: JSON.stringify({ s: { steps } }) });
  return globalThis.__cardguest.drive.size();
};

// Nothing but the root.
check("an untouched card holds one instance", await drive([]), 1);

// The root plus one row, however many interactions it took: typing is a
// transition too, and each supersedes the list.
check("three rows are three instances and a root", await drive([
  ...add("a"), ...add("b"), ...add("c"),
]), 4);

// Twelve rows built by twenty-four interactions. Without the collector this
// was 37 — one per interaction plus the children.
check("interactions do not accumulate", await drive(
  Array.from({ length: 12 }, (_, i) => add(`t${i}`)).flat(),
), 13);

// …and a row that goes, goes. The one the superseded collector cannot see.
check("a dropped row is released", await drive([
  ...add("a"), ...add("b"), ...add("c"),
  { click: "button.drop" }, { click: "button.drop" }, { click: "button.drop" },
]), 1);

if (failed > 0) {
  console.error(`\n${failed} instance check(s) failed`);
  process.exit(1);
}
console.log("\ninstances: all checks pass");
