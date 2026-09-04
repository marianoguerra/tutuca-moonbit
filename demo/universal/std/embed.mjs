// Regenerate `std_card_gen.mbt` from `std.card.html`.
//
//   moon run --target native cmd/dev -- universal-embed   (snapshots + drift-checks)
//
// The `.html` is authoritative; this is a copy of it that MoonBit can reach.
// The page compiles the kit in the browser before it can place anything, so
// the source has to be IN the bundle — a page that fetched it beside itself
// would have a layout kit that arrives after the first render, and the first
// thing the page draws is a hole.
//
// Comments are KEPT, unlike `tgc/rt/embed.mjs`, and the difference is what the
// two files are for. That one embeds a runtime nobody reads at the page; this
// embeds a card that the compiler's own diagnostics point INTO, by line, when
// the kit stops compiling. Dropping the comments would renumber every one.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "std.card.html"), "utf8");

// No ASCII guard here, unlike `tgc/rt/embed.mjs`. That one has one because the
// WAX front end needs it when the source arrives as a literal; MoonBit source
// is UTF-8 and a card's prose is written for people to read.

// FOUR spaces, because that is what `moon fmt` leaves — and a generator whose
// output the formatter then rewrites is a file that is stale the moment it is
// written. The drift check catches it every run.
const lines = source
  .replace(/\n+$/, "")
  .split("\n")
  .map((l) => `    #|${l}`)
  .join("\n");

writeFileSync(
  join(here, "std_card_gen.mbt"),
  `// Generated from \`std.card.html\` by \`node demo/universal/std/embed.mjs\`.
// DO NOT EDIT.
//
// Change \`std.card.html\`, rerun the task, commit both halves.

///|
/// The layout kit, as source.
///
/// It is compiled by the same compiler that compiles anything a person pastes
/// into the page, and registered by the same \`register_module\`. The ONE way it
/// differs is that it is here rather than fetched — which is a fact about when
/// it arrives, not about what it is allowed to do.
pub fn card_source() -> String {
  let src =
${lines}
  src
}
`,
);
console.log(
  `std_card_gen.mbt: ${source.split("\n").length} lines embedded`,
);
