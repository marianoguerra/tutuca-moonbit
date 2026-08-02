#!/usr/bin/env node
// Build this guest end to end:
//
//   moon build --target wasm --release      the MoonBit core module
//   wasm-tools component embed  (utf16)     attach the WIT to it
//   wasm-tools component new                make it a Component-Model component
//   jco transpile --instantiation async     the ESM a browser host can load
//
// Output: dist/<name>.component.wasm and dist/js/. Then `node pack.mjs` turns
// dist/js into the single `.tutuca.tar.gz` you hand to a host.
//
// `wit/` holds the contract this implements — `tutuca:component@0.4.0`, the
// same file the host generates its side from. The bindings in gen/, interface/
// and world/ were generated from it and are checked in, so building needs NO
// wit-bindgen: only moon, wasm-tools, and node.
//
// Prereqs (version-coupled — do not mix):
//   moon v0.10.x · wasm-tools 1.244.x · @bytecodealliance/jco 1.25.x
//
// Install jco with `npm install` here. NOTE: the bare `jco` package on npm is a
// dependency-confusion placeholder — the real one is `@bytecodealliance/jco`,
// which is what package.json names. Never install the other.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const name = JSON.parse(readFileSync(join(here, "package.json"), "utf8")).name;
const dist = join(here, "dist");
const run = (cmd, args) => execFileSync(cmd, args, { stdio: "inherit", cwd: here });

const jco = join(here, "node_modules", "@bytecodealliance", "jco", "src", "jco.js");
if (!existsSync(jco)) {
  console.error("jco is not installed — run `npm install` first");
  process.exit(1);
}

mkdirSync(dist, { recursive: true });

run("moon", ["build", "--target", "wasm", "--release"]);

// utf16 because that is how MoonBit lays out strings; the host's side of the
// canonical ABI is generated from the same WIT and agrees.
run("wasm-tools", [
  "component", "embed", "wit",
  join("_build", "wasm", "release", "build", "gen", "gen.wasm"),
  "--encoding", "utf16",
  "-o", join("dist", `${name}.embedded.wasm`),
]);
run("wasm-tools", [
  "component", "new",
  join("dist", `${name}.embedded.wasm`),
  "-o", join("dist", `${name}.component.wasm`),
]);
// --instantiation async: the host supplies every import itself (there is no
// WASI here — that IS the sandbox), so the module cannot self-instantiate.
run(process.execPath, [
  jco, "transpile", join("dist", `${name}.component.wasm`),
  "--instantiation", "async",
  "-o", join("dist", "js"),
]);

console.log(`\nbuilt dist/${name}.component.wasm and dist/js/`);
console.log("next: node pack.mjs");
