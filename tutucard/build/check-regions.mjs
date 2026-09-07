// The region splitter, checked.
//
// `regions.js` is the one piece of the playground that EDITS the card rather
// than drawing it, and it does so by character offset — so a base computed one
// token wrong splices a rename into the middle of a heading. It has no MoonBit
// to hide behind, and no browser is needed to hold it to its contract.
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
  "spec:",
  "  Counter:",
  "    field n :: Int",
  "",
  "logic:",
  "  Counter:",
  "    receive bump:",
  "      it.n += 1",
  "",
  "view:",
  "  Counter:",
  "    @p{main}",
  "",
  "  Counter.row:",
  "    @b{row}",
  "",
  "fixtures:",
  '  "fresh":',
  "    it.n = 0",
  "",
].join("\n");

const p = R.parts(CARD);
check("the spec section is sliced exactly", p.spec.text, "\n  Counter:\n    field n :: Int");
check("the logic section is sliced exactly", p.script.text, "\n  Counter:\n    receive bump:\n      it.n += 1");
// The examples tab edits this one, and the Examples pane mounts what it names.
check(
  "the fixtures section is sliced exactly",
  p.fixtures.text,
  '\n  "fresh":\n    it.n = 0',
);
// …and a card without one says so rather than throwing, which is what the tab's
// empty state is drawn from.
check("a card with no fixtures section has none", R.parts("view:\n  X:\n    @p{x}\n").fixtures, null);
// A new section is the ENVELOPE, not a bare name: the thing an author opens is
// the thing they should copy.
check(
  "addInit writes a fixture, not a bare name",
  R.addInit("view:\n  X:\n    @p{x}\n").includes('"fresh" ~default:'),
  true,
);
check("views are named by the half after the dot", p.views.map((v) => v.name), ["main", "row"]);

// …unless the file declares more than one component, and then the half after
// the dot names nothing: two components' `main` views would both be `main`,
// and a tab strip is what a reader picks a component with.
const TWO = [
  "spec:",
  "  Todos:",
  "    field n :: Int",
  "",
  "  Todo:",
  "    field t :: String",
  "",
  "view:",
  "  Todos:",
  "    @ul",
  "",
  "  Todo:",
  "    @li",
  "",
  "  Todo.row:",
  "    @b",
  "",
].join("\n");
check(
  "a file with two components names its tabs by component",
  R.parts(TWO).views.map((v) => v.name),
  ["Todos", "Todo", "Todo.row"],
);
check(
  "…and the ids are untouched, so a rename still splices",
  R.parts(TWO).views.map((v) => v.id),
  ["Todos", "Todo", "Todo.row"],
);
check("a view's text is its own", p.views[1].text, "\n    @b{row}");

// The offsets are what everything else stands on.
check(
  "a region's offsets slice back to its text",
  CARD.slice(p.script.start, p.script.end),
  p.script.text,
);
check(
  "an id's offsets slice back to the id",
  CARD.slice(p.views[1].idStart, p.views[1].idEnd),
  "Counter.row",
);

// Splicing is the whole edit path: the structured view writes through it.
check(
  "a splice replaces only its own region",
  R.splice(CARD, p.script, "\n  Counter:\n    receive bump:\n      it.n += 2"),
  CARD.replace("it.n += 1", "it.n += 2"),
);

// A rename edits the heading and NOTHING else, which is the bug this file
// exists for: an offset computed one token wrong splices into the middle of a
// heading.
const renamed = R.renameView(CARD, p, 1, "compact");
check("a rename changes the heading", renamed.includes("Counter.compact:"), true);
check("…and leaves the rest of the card alone", renamed.replace("compact", "row"), CARD);

// Adding a view appends inside `view:`, and nothing else moves.
const added = R.addView(CARD, "edit");
check("adding a view appends a heading", added.includes("  Counter.edit:"), true);
check("…and keeps every character that was there", R.parts(added).spec.text, p.spec.text);
check("…and the new view is the last one", R.parts(added).views.map((v) => v.id).at(-1), "Counter.edit");

const BARE = "spec:\n  Note:\n    field t :: String\n\nview:\n  Note:\n    @p\n";
check("a heading with no dot is the main view", R.parts(BARE).views.map((v) => v.name), ["main"]);

// A card missing a section is not a crash: "there is no logic yet" is what an
// author is about to fix, and the pane says so.
check("a card with no logic section has none", R.parts(BARE).script, null);

// The pane shows the section's body, not where it sits in the file. The pair
// has to compose to the identity on an untouched pane — a projection that
// rewrites the card just by being LOOKED at is worse than an indented pane.
check("a pane starts at column zero", R.dedented(p.views[1].text), "@b{row}");
check("…with no line the heading left behind", R.dedented(p.spec.text), "Counter:\n  field n :: Int");
check(
  "an untouched pane splices back the same characters",
  R.reindented(p.views[1].text, R.dedented(p.views[1].text)),
  p.views[1].text,
);
check(
  "an edited pane comes back indented like the section",
  R.reindented(p.views[1].text, "@b{row}\n@i{and more}"),
  "\n    @b{row}\n    @i{and more}",
);
// A line the author left empty stays empty: indenting it is how a file grows
// the trailing whitespace nobody typed.
check(
  "a blank line comes back blank",
  R.reindented(p.views[1].text, "@b{row}\n\n@i{more}"),
  "\n    @b{row}\n\n    @i{more}",
);

// --- macros ----------------------------------------------------------------
// A `macro …:` is a declaration of the FILE, not a view of the component, so it
// belongs to its own list: collected with the views it would show as a view of
// a component called `macro`.

const WITH_MACRO = [
  "spec:",
  "  Form:",
  "    field name :: String",
  "",
  "view:",
  '  macro field(~label: "Field"):',
  "    @label{@span{@(label)} @slot}",
  "",
  "  Form:",
  '    @div{@field(~label: "Name")}',
  "",
].join("\n");

const pm = R.parts(WITH_MACRO);
check("one macro", pm.macros.length, 1);
check("the macro's name is what follows `macro`", pm.macros[0].name, "field");
check("the macro is not counted as a view", pm.views.length, 1);
check("…and the real view is still main", pm.views[0].name, "main");
check("the macro region is its body", WITH_MACRO.slice(pm.macros[0].start, pm.macros[0].end).includes("@slot"), true);

const renamedMacro = R.renameMacro(WITH_MACRO, pm, 0, "row");
check("renaming a macro edits its heading", renamedMacro.includes("macro row("), true);
check("…and does not turn it into a view", R.parts(renamedMacro).views.length, 1);

const addedMacro = R.addMacro(WITH_MACRO, "row");
const pa = R.parts(addedMacro);
check("an added macro joins the macro list", pa.macros.length, 2);
check("…under the name it was given", pa.macros.map((m) => m.name).includes("row"), true);
check(
  "…with a slot, since a macro without one drops its children",
  pa.macros.find((m) => m.name === "row").text.includes("@slot"),
  true,
);
check("…and the views are untouched", pa.views.length, 1);

console.log(failed === 0 ? "\nregions: all checks pass" : `\n${failed} region check(s) failed`);
process.exit(failed === 0 ? 0 : 1);
