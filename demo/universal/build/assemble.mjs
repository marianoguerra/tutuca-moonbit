// Assemble `dist/universal/`.
//
// A script rather than a list of copy steps, because two of the pieces are not
// files that already exist: the runtime module has to be built, and the sample
// cards are copied out of `tutucard/examples` with an index written beside
// them. A `Copy` cannot do either.
//
// What lands here:
//
//   universal.js      the page, built by `moon build --target js`
//   page.js           its JS half — instantiate, fetch, drop
//   card.js           the `tgc` loader, and `values.mjs` beside it
//   tutuca-rt.wasm    the runtime every card is instantiated against
//   cards/*.html      the sample cards, uncompiled, with an index.json
//   index.html        with the script path repointed at the copy above
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { copyTgcValues } from "../../../scripts/tgc-values.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..", "..");
const OUT = join(REPO, "dist", "universal");
const BUILT = "_build/js/debug/build/demo/universal/universal.js";

mkdirSync(join(OUT, "cards"), { recursive: true });

// The page itself.
copyFileSync(join(REPO, BUILT), join(OUT, "universal.js"));
copyFileSync(join(HERE, "..", "page.js"), join(OUT, "page.js"));

// The loader, and the value codec it imports. `copyTgcValues` is the one place
// that knows how `card.js`'s import of `values.mjs` gets rewritten for a flat
// directory — a second copy of that rewrite is how the two come to disagree.
copyFileSync(join(REPO, "tutucard", "web", "card.js"), join(OUT, "card.js"));
copyTgcValues(OUT);

// The runtime, from its EMBEDDED source rather than from `rt.wax`. It is the
// route a page takes, so it is the route worth building.
execFileSync(
  "moon",
  ["run", "--target", "native", "cmd/tgc", "--", "runtime", join(OUT, "tutuca-rt.wasm")],
  { cwd: REPO, stdio: "inherit" },
);

// The sample cards, as SOURCE. They are compiled in the browser, on demand,
// which is the demo's point rather than a tax: shipping compiled bytes beside
// the source would put a second copy of every card in the tree with no way to
// tell whether the two still agree.
const FROM = join(REPO, "tutucard", "examples");
const rows = [];
for (const f of readdirSync(FROM).filter((n) => n.endsWith(".html")).sort()) {
  copyFileSync(join(FROM, f), join(OUT, "cards", f));
  rows.push({ name: f.replace(/\.html$/, ""), path: `cards/${f}` });
}
writeFileSync(join(OUT, "cards", "index.json"), JSON.stringify(rows, null, 2) + "\n");

// The page, with the script path repointed from `_build` to the copy beside it.
const page = readFileSync(join(HERE, "..", "index.html"), "utf8");
const repointed = page.replace(`../../${BUILT}`, "./universal.js");
if (repointed === page) {
  throw new Error(
    `index.html no longer references ${BUILT}; the dist copy would load nothing`,
  );
}
writeFileSync(join(OUT, "index.html"), repointed);

console.log(`dist/universal: the page, the runtime and ${rows.length} cards`);
