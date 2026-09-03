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
const wax = readFileSync(join(here, "rt.wax"), "utf8");
const lines = wax.split("\n").map((l) => `  #|${l}`).join("\n");

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
console.log(`rt_src_gen.mbt: ${wax.split("\n").length} lines embedded`);
