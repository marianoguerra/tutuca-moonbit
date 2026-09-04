// Copy the value bridge into a dist folder, and repoint `card.js` at it.
//
// `tgc/host/values.mjs` is `core.Value` JSON <-> `tg_val`, and it is written
// ONCE — a second copy is a second answer to what a value is. Two assemblers
// need it beside `card.js` (the card playground and the landing site), and both
// have to rewrite the same import specifier, because the source lives two
// directories up from `tutucard/web` and flat beside it in dist. Rewriting one
// specifier is cheaper than making the repository layout match a dist layout it
// has no other reason to have.
//
// Shared so the pair — the copy and the rewrite — cannot come apart in one
// assembler and not the other: a copy without the rewrite leaves `card.js`
// importing a path that is not there, which fails only in the browser.
import { cpSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");

/// `out` must already contain `card.js`.
export function copyTgcValues(out) {
  cpSync(join(REPO, "tgc", "host", "values.mjs"), join(out, "tgc-values.mjs"));
  const card = join(out, "card.js");
  writeFileSync(
    card,
    readFileSync(card, "utf8").replace(
      "../../tgc/host/values.mjs",
      "./tgc-values.mjs",
    ),
  );
}
