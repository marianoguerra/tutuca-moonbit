// The region splitter, checked.
//
// `regions.js` is the one piece of the playground that EDITS the card rather
// than drawing it, and it does so by character offset — so a base computed one
// token wrong splices a rename into the middle of a tag. It has no MoonBit to
// hide behind, and no browser is needed to hold it to its contract.
//
// Run by the `tutucard-playground` task, beside check-examples.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const R = await import(pathToFileURL(join(HERE, "..", "web", "regions.js")).href);

let failed = 0;
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) {
    failed++;
    console.error(`✗ ${name}\n    got  ${JSON.stringify(got)}\n    want ${JSON.stringify(want)}`);
  } else {
    console.log(`ok      ${name}`);
  }
}

const CARD = [
  '<script type="tutuca/state">',
  "  state Counter { n: Int }",
  "</script>",
  "",
  '<script type="tutuca/script">',
  "  on bump { .n += 1 }",
  "</script>",
  "",
  '<template id="Counter">',
  "  <p>main</p>",
  "</template>",
  '<template id="Counter:row">',
  "  <b>row</b>",
  "</template>",
  "",
].join("\n");

const p = R.parts(CARD);
check("the state block is sliced exactly", p.state.text, "\n  state Counter { n: Int }\n");
check("the script block is sliced exactly", p.script.text, "\n  on bump { .n += 1 }\n");
check("views are named by the half after the colon", p.views.map((v) => v.name), ["main", "row"]);
check("a view's text is its own", p.views[1].text, "\n  <b>row</b>\n");

// The offsets are what everything else stands on.
check(
  "a region's offsets slice back to its text",
  CARD.slice(p.script.start, p.script.end),
  p.script.text,
);
check(
  "an id's offsets slice back to the id",
  CARD.slice(p.views[1].idStart, p.views[1].idEnd),
  "Counter:row",
);

// Splicing is the whole edit path: the structured view writes through it.
check(
  "a splice replaces only its own region",
  R.splice(CARD, p.script, "\n  on bump { .n += 2 }\n"),
  CARD.replace(".n += 1", ".n += 2"),
);

// A rename edits the id and NOTHING else, which is the bug this file exists
// for: the offset was computed from `<template` + 1 rather than + 9, and the
// splice landed inside the tag.
const renamed = R.renameView(CARD, p, 1, "compact");
check("a rename changes the id", renamed.includes('id="Counter:compact"'), true);
check("…and leaves the rest of the card alone", renamed.replace("compact", "row"), CARD);

// Adding a view appends, and names the bare template on the way if it has to.
const added = R.addView(CARD, "edit");
check("adding a view appends a template", added.includes('<template id="Counter:edit">'), true);
check("…and keeps everything that was there", added.startsWith(CARD), true);

const BARE = '<script type="tutuca/state">\n  state Note { t: String }\n</script>\n<template><p></p></template>\n';
check("a bare template is the main view", R.parts(BARE).views.map((v) => v.name), ["main"]);
const named = R.addView(BARE, "edit");
check(
  "…and adding a second view names the first",
  named.includes('<template id="Note">') && named.includes('<template id="Note:edit">'),
  true,
);

// A card missing a block is not a crash: "there is no script yet" is what an
// author is about to fix, and the pane says so.
check("a card with no script block has none", R.parts(BARE).script, null);

console.log(failed === 0 ? "\nregions: all checks pass" : `\n${failed} region check(s) failed`);
process.exit(failed === 0 ? 0 : 1);
