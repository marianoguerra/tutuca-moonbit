// The host holds one instance per live component and not one more.
//
// This used to count a TABLE. The bridge named every instance with an integer
// so that MoonBit had something it could hold, and the table that mapped those
// integers back was a strong reference to everything ever made — so a card left
// open on a page grew forever, and two collectors existed to repair it: one for
// the predecessor a successor replaced, and a reachability sweep for the row
// that was simply removed and superseded by nothing.
//
// There is no table. The host holds the instance itself, the engine collects it
// when the host stops, and what is left to check is the only thing that was
// ever really being asked: does the TREE grow. `live_instances` walks the root
// and counts what it reaches, which is the same question the sweep answered and
// a more direct way to ask it.
//
// The numbers are unchanged and still exact rather than a bound: a card with
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
  join(REPO, "tutucard", "examples", "Todos.html"),
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
  return globalThis.__tutucard.instanceCount();
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
