// Check runtime/*.wax against the vendored stdlib, using the wax CLI.
//
// A fast loop for editing the runtime: `moon test` has to rebuild the
// generator to tell you about a typo in a `.wax` file, and the CLI does not.
// The concatenation here MUST match `emit_module`'s field order; the MoonBit
// test in `runtime_test.mbt` is the one that holds it to that.
//
// usage: node tutucard/wasm/build/check-runtime.mjs [scalar|values]  (both)

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const MODULE = join(HERE, "..");
const WAX = "/home/mariano/src/mb/wax/tools/wax-mb";

const STDLIB = [
  "hashing.wax",
  "persistent_hash_map.wax",
  "persistent_hash_set.wax",
  "persistent_vector.wax",
  "utf8.wax",
  "immutable_value.wax",
  "record.wax",
];

// What the generator puts between the stdlib and the runtime. Kept in step
// with `emit_module` by `gen/runtime_test.mbt`, which compiles the same shape
// through the same library the generator uses.
const PRELUDE = `memory mem: i32 [2];
let heap: i32 = 1024;
fn alloc(size: i32, align: i32) -> i32 {
    let base = (heap + align - 1) /u align * align;
    let end = base + size;
    let have = mem.size() * 65536;
    if end >s have {
        let need = (end - have + 65535) /u 65536;
        if mem.grow(need) <s 0 { return 0; }
    }
    heap = end;
    base
}
`;

// Carried only by a card that uses what is in them, and appended after the
// lowering half. Checked here unconditionally: the point of this script is to
// compile every line of `runtime/`, and a piece only some cards get is exactly
// the piece a typo hides in.
const OPTIONAL = ["parse_num.wax", "send_at.wax", "contract_log.wax", "escape_help.wax"];

function build(lowering) {
  const parts = [];
  const spans = [];
  let line = 1;
  const add = (name, text) => {
    const n = text.split("\n").length - 1;
    spans.push([line, line + n - 1, name]);
    line += n;
    parts.push(text);
  };
  for (const n of STDLIB) add(`vendor/wax/${n}`, readFileSync(join(MODULE, "vendor", "wax", n), "utf8") + "\n");
  add("<prelude>", PRELUDE);
  add("runtime/runtime.wax", readFileSync(join(MODULE, "runtime", "runtime.wax"), "utf8") + "\n");
  add(`runtime/${lowering}`, readFileSync(join(MODULE, "runtime", lowering), "utf8") + "\n");
  for (const n of OPTIONAL) add(`runtime/${n}`, readFileSync(join(MODULE, "runtime", n), "utf8") + "\n");
  return { src: parts.join(""), spans };
}

// The CLI reports lines into the concatenation; a reader wants a file and a
// line they can open.
function rebase(spans, out) {
  return out.replace(/^(\s*)(\d+)( │)/gm, (all, pad, num, tail) => {
    const n = Number(num);
    const hit = spans.find(([a, b]) => n >= a && n <= b);
    return hit ? `${pad}${hit[2]}:${n - hit[0] + 1}${tail}` : all;
  });
}

let bad = 0;
for (const lowering of process.argv[2] ? [`lower_${process.argv[2]}.wax`] : ["lower_scalar.wax", "lower_values.wax"]) {
  const { src, spans } = build(lowering);
  const dir = mkdtempSync(join(tmpdir(), "cardwasm-"));
  const file = join(dir, "all.wax");
  writeFileSync(file, src);
  try {
    execFileSync(WAX, ["convert", "-f", "wasm", "-o", join(dir, "out.wasm"), file], { stdio: "pipe" });
    console.log(`ok   ${lowering}`);
  } catch (e) {
    bad = 1;
    const out = (e.stdout?.toString() ?? "") + (e.stderr?.toString() ?? "");
    console.log(`FAIL ${lowering}`);
    console.log(rebase(spans, out).split("\n").slice(0, 40).join("\n"));
  }
}
process.exit(bad);
