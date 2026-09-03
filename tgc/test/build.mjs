// Build every prototype module, by the three routes the proof needs.
//
//   *.body.wat   a module BODY. This script wraps it in the canonical preamble,
//                the way a generator would. The author never types the types.
//   *.whole.wat  a COMPLETE module carrying its own preamble, spelled its own
//                way. This is the "different toolchain" leg: nothing about it
//                came from this repo except the shape of the group.
//   *.wax        compiled by `cmd/tgc`, which prepends the same preamble and
//                hands it to the Wax compiler. A real compiler emitted these
//                types, not a person.
//
// Run: node tgc/test/build.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const proto = join(root, "tgc/proto");
const rt = join(root, "tgc/rt");
const out = join(root, "_build/tgc");

const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { cwd: root, encoding: "utf8", ...opts });

/** The canonical preamble, straight from `tgc/abi` — never a second copy. */
export function preambleWat() {
  return run("moon", ["run", "--target", "native", "cmd/tgc", "--", "preamble", "--wat"]);
}

function assemble(watText, name) {
  const watPath = join(out, `${name}.wat`);
  const wasmPath = join(out, `${name}.wasm`);
  writeFileSync(watPath, watText);
  run("wasm-tools", ["parse", watPath, "-o", wasmPath]);
  run("wasm-tools", ["validate", wasmPath]);
  return wasmPath;
}

export function buildAll() {
  mkdirSync(out, { recursive: true });
  const preamble = preambleWat();
  const built = {};

  const bodies = [
    ...readdirSync(rt).filter((f) => f.endsWith(".body.wat")).map((f) => [rt, f]),
    ...readdirSync(proto).filter((f) => f.endsWith(".body.wat")).map((f) => [proto, f]),
  ];
  for (const [dir, file] of bodies) {
    const name = file.replace(/\.body\.wat$/, "");
    const body = readFileSync(join(dir, file), "utf8");
    built[name] = assemble(`(module\n${preamble}\n${body}\n)\n`, name);
  }

  for (const file of readdirSync(proto).filter((f) => f.endsWith(".whole.wat"))) {
    const name = file.replace(/\.whole\.wat$/, "");
    built[name] = assemble(readFileSync(join(proto, file), "utf8"), name);
  }

  const waxen = [
    ...readdirSync(rt).filter((f) => f.endsWith(".wax")).map((f) => [rt, f]),
    ...readdirSync(proto).filter((f) => f.endsWith(".wax")).map((f) => [proto, f]),
  ];
  for (const [dir, file] of waxen) {
    const name = file.replace(/\.wax$/, "");
    const wasmPath = join(out, `${name}.wasm`);
    const said = run("moon", [
      "run", "--target", "native", "cmd/tgc", "--",
      "build", join(dir, file), wasmPath,
    ]);
    if (said.includes("rejected")) throw new Error(`${file}\n${said}`);
    run("wasm-tools", ["validate", wasmPath]);
    built[name] = wasmPath;
  }
  return built;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const built = buildAll();
  for (const [name, path] of Object.entries(built)) console.log(`${name}: ${path}`);
}
