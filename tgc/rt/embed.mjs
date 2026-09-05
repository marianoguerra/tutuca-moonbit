// Regenerate `rt_src_gen.mbt` from `rt.wap`.
//
//   moon run --target native cmd/dev -- rt-embed   (snapshots + drift-checks)
//
// The `.wap` is authoritative; this is a copy of it that MoonBit can reach. The
// alternative is a page fetching a file out of this repository's `_build`,
// which is precisely what a consumer cannot do.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// COMMENTS ARE DROPPED, and not only for size. `rt.wap` is the authoritative
// copy and the one a person reads; this is a build artifact, and its comments
// are the same words twice. It also keeps the embedded copy ASCII, which the
// front end needs here in a way it does not need from a file — see the note in
// `moon.pkg`.
//
// wap is INDENTATION-SENSITIVE, which the Wax this replaced was not, so dropping
// lines is a sharper knife than it was: a comment line goes whole, never a
// prefix of a line, and blank runs collapse rather than disappear. What says
// this is safe is not the rule but `runtime_matches_source_test`, which compiles
// both copies and compares the bytes.
const source = readFileSync(join(here, "rt.wap"), "utf8");
const kept = source
  .split("\n")
  .filter((l) => !l.trim().startsWith("//"))
  .join("\n")
  .replace(/\n{3,}/g, "\n\n");
const nonAscii = [...kept].filter((c) => c.codePointAt(0) > 127);
if (nonAscii.length) {
  throw new Error(
    `rt.wap has non-ASCII outside a comment (${JSON.stringify(nonAscii.join(""))}); ` +
      "the embedded copy has to be ASCII",
  );
}
// FOUR spaces, because that is what `moon fmt` leaves — and a generator whose
// output the formatter then rewrites is a file that is stale the moment it is
// written. The drift check below would catch it every run.
const lines = kept.split("\n").map((l) => `    #|${l}`).join("\n");

writeFileSync(
  join(here, "rt_src_gen.mbt"),
  `// Generated from \`rt.wap\` by \`node tgc/rt/embed.mjs\`. DO NOT EDIT.
//
// Change \`rt.wap\`, rerun the script, commit both halves.

///|
pub fn source() -> String {
  let src =
${lines}
  src
}
`,
);
console.log(`rt_src_gen.mbt: ${kept.split("\n").length} lines embedded (comments dropped)`);
