// Fetch the in-browser MoonBit compiler (`moonc-web.cjs`) that the playground
// needs, into playground/vendor/. The blob is NOT committed (it is 5+ MB and
// gitignored); this script pulls it from npm on demand.
//
// IMPORTANT — toolchain coupling: the playground bakes the *installed* `moon`
// toolchain's core `.mi`/`.core` bundles into its payload (see assemble.mjs),
// so the fetched `moonc-web.cjs` MUST be built from the same `moonc` version.
// The npm package `@moonbit/moonc-worker` publishes date-versioned nightly
// builds; there is no exact-hash selector. Both halves of that pair are pinned
// in ONE place — playground/build/toolchain.json — which this script and
// assemble.mjs both read, so they cannot drift apart from each other.
//
// Run directly:  node playground/build/fetch-compiler.mjs [--force]
// Or import:     import { ensureCompiler } from "./fetch-compiler.mjs"
import { existsSync, mkdirSync, cpSync, rmSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const HERE = dirname(fileURLToPath(import.meta.url));

/// The one toolchain pin: { mooncWorker, moonc, mooncBuild, moon }. Read rather
/// than duplicated so a bump is a single-file edit.
export const TOOLCHAIN = JSON.parse(
  readFileSync(join(HERE, "toolchain.json"), "utf8"),
);
export const MOONC_WORKER_VERSION = TOOLCHAIN.mooncWorker;

const REPO = join(HERE, "..", "..");
const VENDOR = join(REPO, "playground/vendor");
const TARGET = join(VENDOR, "moonc-web.cjs");

/// Ensure playground/vendor/moonc-web.cjs exists. Downloads the pinned
/// @moonbit/moonc-worker from npm when missing (or when force is true).
/// Returns the path to the vendored compiler.
export function ensureCompiler({ force = false } = {}) {
  if (existsSync(TARGET) && !force) return TARGET;

  const spec = `@moonbit/moonc-worker@${MOONC_WORKER_VERSION}`;
  console.log(`fetching ${spec} → playground/vendor/moonc-web.cjs`);

  const work = join(tmpdir(), `tutuca-moonc-${process.pid}`);
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  try {
    // npm pack handles registry resolution + tarball download.
    const tgz = execSync(`npm pack ${spec} --pack-destination "${work}"`, {
      cwd: work,
      encoding: "utf8",
    }).trim().split("\n").pop();
    execSync(`tar xzf "${join(work, tgz)}" -C "${work}"`, { stdio: "inherit" });
    mkdirSync(VENDOR, { recursive: true });
    // The package ships moonc-web.cjs (+ .d.ts) under package/.
    cpSync(join(work, "package/moonc-web.cjs"), TARGET);
    const dts = join(work, "package/moonc-web.d.ts");
    if (existsSync(dts)) cpSync(dts, join(VENDOR, "moonc-web.d.ts"));
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  console.log("done: playground/vendor/moonc-web.cjs");
  return TARGET;
}

// CLI entry point.
if (import.meta.url === `file://${process.argv[1]}`) {
  ensureCompiler({ force: process.argv.includes("--force") });
}
