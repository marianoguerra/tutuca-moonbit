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
import {
  existsSync,
  mkdirSync,
  cpSync,
  rmSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
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

/// What the vendored blob IS, beside the blob.
///
/// The registry normalizes SemVer build metadata away — `npm view` reports
/// `0.1.202608243` for a package whose own `package.json` says
/// `0.1.202608243+f8a486b6f` — so the moonc a worker was built from is
/// knowable only from inside the tarball. Recording it here is what lets a
/// later run answer "is the blob on disk the one this toolchain needs?"
/// without downloading 5 MB to find out.
const STAMP = join(VENDOR, "moonc-web.json");

/// The `+build` half of a version, or null.
function buildOf(version) {
  const plus = version.indexOf("+");
  return plus < 0 ? null : version.slice(plus + 1);
}

/// The installed toolchain, as the two things that identify a moonc: the
/// version string toolchain.json pins, and the build hash a published worker
/// carries in its own version.
export function installedToolchain(cwd = REPO) {
  const raw = execSync("moon version --all", { cwd, encoding: "utf8" });
  const moonc = raw.match(/moonc (v[\d.]+\+[0-9a-f]+)/);
  const moon = raw.match(/^moon (\S+)/m);
  return {
    raw,
    moonc: moonc ? moonc[1] : null,
    build: moonc ? buildOf(moonc[1]) : null,
    moon: moon ? moon[1] : null,
  };
}

/// What the vendored blob was built from, or null when it is absent or
/// unstamped (a blob dropped in by hand, which the README allows).
export function vendoredWorker() {
  if (!existsSync(TARGET) || !existsSync(STAMP)) return null;
  try {
    return JSON.parse(readFileSync(STAMP, "utf8")).version;
  } catch {
    return null;
  }
}

/// Download one published worker into playground/vendor/, and answer the
/// version its own package.json claims — with the `+build` the registry drops.
export function fetchWorker(version) {
  const spec = `@moonbit/moonc-worker@${version}`;
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
    const own = JSON.parse(
      readFileSync(join(work, "package/package.json"), "utf8"),
    ).version;
    writeFileSync(STAMP, JSON.stringify({ version: own }, null, 2) + "\n");
    console.log(`done: playground/vendor/moonc-web.cjs (${own})`);
    return own;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

/// Ensure playground/vendor/moonc-web.cjs is the worker `version`, built from
/// moonc `build`. Downloads it when the vendored blob is absent or is another
/// one. Returns the path to the vendored compiler.
///
/// Both default to the PIN, which is what a caller with nothing else to go on
/// wants. `assemble.mjs` passes the pair it settled on instead, because when
/// the pin is the stale half of the disagreement, "restore the pin" is exactly
/// the wrong repair.
export function ensureCompiler({
  force = false,
  version = MOONC_WORKER_VERSION,
  build = TOOLCHAIN.mooncBuild,
} = {}) {
  // A blob whose stamp names another build is one an earlier pin left behind,
  // and keeping it would be the one failure this whole file exists to prevent
  // — silently. An UNSTAMPED blob is left alone: the README says a matching
  // worker npm does not publish can be dropped in here by hand, and
  // overwriting that would break the escape hatch.
  const have = vendoredWorker();
  const other = have !== null && !have.endsWith(`+${build}`);
  if (existsSync(TARGET) && !force && !other) return TARGET;
  fetchWorker(version);
  return TARGET;
}

/// Fetch the published worker built from `build` (a moonc hash) and answer its
/// version, or null when none is published.
///
/// `@moonbit/moonc-worker` has no exact-hash selector — which is the whole
/// reason toolchain.json exists — but it does have a CONVENTION: the worker
/// for `moon 0.1.<YYYYMMDD>` is `0.1.<YYYYMMDD><n>`. So the day narrows the
/// list to a candidate or two and the tarball's own version settles it. The
/// convention is a search ORDER and not a claim: a candidate that turns out
/// not to carry the hash is skipped, so a day that published two workers, or
/// none, is handled by looking rather than by believing.
///
/// Downloading is how a candidate is checked, because the registry does not
/// keep the build metadata. That is the cost of being wrong about the first
/// guess, and the first guess is right whenever the toolchain and its worker
/// were published on the same day — which is every case so far.
export function resolveWorkerForBuild(build, moon) {
  const versions = JSON.parse(
    execSync("npm view @moonbit/moonc-worker versions --json", {
      encoding: "utf8",
    }),
  );
  const day = (moon ?? "").split(".").pop();
  const sameDay = day ? versions.filter((v) => v.startsWith(`0.1.${day}`)) : [];
  const candidates = [
    ...sameDay.reverse(),
    // Then the newest few, for a worker published a day after its toolchain.
    ...versions.slice(-4).reverse().filter((v) => !sameDay.includes(v)),
  ];
  for (const v of candidates) {
    if (buildOf(fetchWorker(v)) === build) return v;
    console.log(`  ${v} is not built from ${build} — trying the next`);
  }
  return null;
}

// CLI entry point.
if (import.meta.url === `file://${process.argv[1]}`) {
  ensureCompiler({ force: process.argv.includes("--force") });
}
