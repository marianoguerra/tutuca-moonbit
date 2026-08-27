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
  '<script type="tutuca/spec">',
  "  state Counter { n: Int }",
  "</script>",
  "",
  '<script type="tutuca/script">',
  "  receive bump { .n += 1 }",
  "</script>",
  "",
  '<script type="tutuca/init">',
  '  { "fresh": { "value": { "n": 0 } } }',
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
check("the script block is sliced exactly", p.script.text, "\n  receive bump { .n += 1 }\n");
// The examples tab edits this one, and the Examples pane mounts what it names.
check(
  "the init block is sliced exactly",
  p.init.text,
  '\n  { "fresh": { "value": { "n": 0 } } }\n',
);
// …and a card without one says so rather than throwing, which is what the tab's
// empty state is drawn from.
check("a card with no init block has none", R.parts("<template><p>x</p></template>").init, null);
// A new block is the ENVELOPE, not a bare field map: the format has no
// shorthand, and the thing an author opens is the thing they should copy.
check(
  "addInit writes a fixture, not a field map",
  R.addInit("<template><p>x</p></template>\n").includes('"value": {}'),
  true,
);
check("views are named by the half after the colon", p.views.map((v) => v.name), ["main", "row"]);

// …unless the file declares more than one component, and then the half after
// the colon names nothing: two components' `main` views would both be `main`,
// and a tab strip is what a reader picks a component with.
const TWO = [
  '<script type="tutuca/spec">',
  "  state Todos { n: Int }",
  "  state Todo { t: String }",
  "</script>",
  '<template id="Todos:main">',
  "  <ul></ul>",
  "</template>",
  '<template id="Todo:main">',
  "  <li></li>",
  "</template>",
  '<template id="Todo:row">',
  "  <b></b>",
  "</template>",
  "",
].join("\n");
check(
  "a file with two components names its tabs by component",
  R.parts(TWO).views.map((v) => v.name),
  ["Todos", "Todo", "Todo:row"],
);
check(
  "…and the ids are untouched, so a rename still splices",
  R.parts(TWO).views.map((v) => v.id),
  ["Todos:main", "Todo:main", "Todo:row"],
);
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
  R.splice(CARD, p.script, "\n  receive bump { .n += 2 }\n"),
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

const BARE = '<script type="tutuca/spec">\n  state Note { t: String }\n</script>\n<template><p></p></template>\n';
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

// The pane shows the block's body, not where the block sits in the file. The
// pair has to compose to the identity on an untouched pane — a projection that
// rewrites the card just by being LOOKED at is worse than an indented pane.
check("a pane starts at column zero", R.dedented(p.views[1].text), "<b>row</b>");
check("…with no line the tags left behind", R.dedented(p.state.text), "state Counter { n: Int }");
check(
  "an untouched pane splices back the same characters",
  R.reindented(p.views[1].text, R.dedented(p.views[1].text)),
  p.views[1].text,
);
check(
  "an edited pane comes back indented like the block",
  R.reindented(p.views[1].text, "<b>row</b>\n<i>and more</i>"),
  "\n  <b>row</b>\n  <i>and more</i>\n",
);
// A line the author left empty stays empty: indenting it is how a file grows
// the trailing whitespace nobody typed.
check(
  "a blank line comes back blank",
  R.reindented(p.views[1].text, "<b>row</b>\n\n<i>more</i>"),
  "\n  <b>row</b>\n\n  <i>more</i>\n",
);
// Content on the tag's own line has no indentation to take, and inventing one
// would rewrite the line on the first keystroke.
const inline = R.parts(BARE).views[0];
check("an inline template is left as it is", R.dedented(inline.text), "<p></p>");
check(
  "…and splices back as it is",
  R.reindented(inline.text, "<p>hi</p>"),
  "<p>hi</p>",
);


// --- macros ----------------------------------------------------------------
// A `<template id="macro:…">` is a declaration of the FILE, not a view of the
// component, so it belongs to its own list: collected with the views it would
// show as a view called `field` of a component called `macro`.

const WITH_MACRO = [
  '<script type="tutuca/spec">',
  "  state Form { name : String }",
  "</script>",
  '<template id="macro:field" data-label="\'Field\'">',
  "  <label><span @text=\"^label\"></span><x:slot></x:slot></label>",
  "</template>",
  '<template id="Form">',
  '  <div><x:field label="Name"></x:field></div>',
  "</template>",
  "",
].join("\n");

const pm = R.parts(WITH_MACRO);
check("one macro", pm.macros.length, 1);
check("the macro's name is what follows `macro:`", pm.macros[0].name, "field");
check("the macro is not counted as a view", pm.views.length, 1);
check("…and the real view is still main", pm.views[0].name, "main");
check("the macro region is its body", WITH_MACRO.slice(pm.macros[0].start, pm.macros[0].end).includes("x:slot"), true);

const renamedMacro = R.renameMacro(WITH_MACRO, pm, 0, "row");
check("renaming keeps the macro: prefix, which is what makes it a macro", renamedMacro.includes('<template id="macro:row"'), true);
check("…and does not turn it into a view", R.parts(renamedMacro).views.length, 1);

const addedMacro = R.addMacro(WITH_MACRO, "row");
const pa = R.parts(addedMacro);
check("an added macro joins the macro list", pa.macros.length, 2);
check("…under the name it was given", pa.macros[1].name, "row");
check("…with a slot, since a macro without one drops its children", pa.macros[1].text.includes("<x:slot>"), true);
check("…and the views are untouched", pa.views.length, 1);

console.log(failed === 0 ? "\nregions: all checks pass" : `\n${failed} region check(s) failed`);
process.exit(failed === 0 ? 0 : 1);
