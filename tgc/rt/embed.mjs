// Regenerate `rt_src_gen.mbt` from `rt.wax`.
//
//   node tgc/rt/embed.mjs
//
// The `.wax` is authoritative; this is a copy of it that MoonBit can reach. The
// alternative is a page fetching a file out of this repository's `_build`,
// which is precisely what a consumer cannot do.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// COMMENTS ARE DROPPED, and not only for size. `rt.wax` is the authoritative
// copy and the one a person reads; this is a build artifact, and its comments
// are the same words twice. It also keeps the embedded copy ASCII, which the
// Wax front end needs here in a way it does not need from a file — see the
// note in `moon.pkg`.
const source = readFileSync(join(here, "rt.wax"), "utf8");
const kept = source
  .split("\n")
  .filter((l) => !l.trim().startsWith("//"))
  .join("\n")
  .replace(/\n{3,}/g, "\n\n");
const nonAscii = [...kept].filter((c) => c.codePointAt(0) > 127);
if (nonAscii.length) {
  throw new Error(
    `rt.wax has non-ASCII outside a comment (${JSON.stringify(nonAscii.join(""))}); ` +
      "the embedded copy has to be ASCII",
  );
}
// FOUR spaces, because that is what `moon fmt` leaves — and a generator whose
// output the formatter then rewrites is a file that is stale the moment it is
// written. The drift check below would catch it every run.
const lines = kept.split("\n").map((l) => `    #|${l}`).join("\n");

writeFileSync(
  join(here, "rt_src_gen.mbt"),
  `// Generated from \`rt.wax\` by \`node tgc/rt/embed.mjs\`. DO NOT EDIT.
//
// Change \`rt.wax\`, rerun the script, commit both halves.

///|
pub fn source() -> String {
  let src =
${lines}
  src
}
`,
);
console.log(`rt_src_gen.mbt: ${kept.split("\n").length} lines embedded (comments dropped)`);
