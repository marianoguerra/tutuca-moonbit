// Fetch the stock Tailwind stylesheets that the `css-bundle` dev task resolves
// css/assets/tailwind.entry.css's `@import`s against, into the gitignored
// _build/tailwind/tw/.
//
// These files come from the published `tailwindcss` npm tarball, NOT from the
// margaui checkout. margaui carries its own tw/*.css, but its own README calls
// them a manual mirror, and they lag: at v0.5606.3 they were still missing the
// mauve/olive/mist/taupe palettes upstream added in 4.3.2, on top of the 4.3.3
// deltas. The compiler we run them through — marianoguerra/tailwindcss — is
// ported from one exact upstream tag, so the stylesheets have to come from that
// same tag or the engine and its data disagree. `checkPin()` below enforces it.
//
// The pin is what makes the regen reproducible — the committed
// css/assets/tailwind.bundle.json + css/tailwind_bundle_gen.mbt are exactly what
// this version produces. To pick up a new Tailwind: upgrade the
// marianoguerra/tailwindcss dependency, bump TW_VERSION to match its new
// UPSTREAM.md tag, re-run `moon run --target native cmd/dev -- css-bundle`, and
// commit the pin together with the regenerated bundle.
//
// Run directly:  node scripts/fetch-tailwind.mjs [--version <v>] [--force]
// Or import:     import { ensureTailwind } from "./fetch-tailwind.mjs"
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// The Tailwind release the committed bundle was generated from. Must equal the
// `Tag:` in the compiler port's UPSTREAM.md — see checkPin().
export const TW_VERSION = "4.3.3";

// The three files upstream's `@import "tailwindcss"` expands to. utilities.css
// is a one-liner (`@tailwind utilities;`) but travels with the other two so the
// entry's import graph resolves entirely from the bundle.
const FILES = ["theme.css", "preflight.css", "utilities.css"];

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TARGET = join(ROOT, "_build/tailwind");
// Where the entry's `./tw/*` imports resolve to, which is also what keys the
// generated bundle — margaui's entry asks for the same paths, so one file map
// serves both compiles.
const TW_DIR = join(TARGET, "tw");
// Records which version TW_DIR holds, so a bumped TW_VERSION re-downloads
// instead of reusing a stale extraction.
const STAMP = join(TARGET, ".tutuca-tailwind-version");

const UPSTREAM_MD = join(ROOT, ".mooncakes/marianoguerra/tailwindcss/UPSTREAM.md");

/// Fail loudly when the pin here drifts from the tag the MoonBit compiler was
/// ported from. Silent drift between the two is exactly how the previously
/// embedded stylesheets ended up a minor version behind the engine reading them.
export function checkPin({ version = TW_VERSION } = {}) {
  if (!existsSync(UPSTREAM_MD)) {
    // A consumer checkout without .mooncakes populated: nothing to compare
    // against, and `moon install` is not this script's job.
    console.warn(`warning: ${UPSTREAM_MD} not found — skipping the version-pin check`);
    return;
  }
  const tag = readFileSync(UPSTREAM_MD, "utf8").match(/^-\s*Tag:\s*`?v?([\d.]+)`?/m);
  if (!tag) {
    throw new Error(`cannot read the ported Tailwind tag from ${UPSTREAM_MD}`);
  }
  if (tag[1] !== version) {
    throw new Error(
      `TW_VERSION is ${version} but marianoguerra/tailwindcss is ported from ` +
        `v${tag[1]} (${UPSTREAM_MD}).\n` +
        `The stylesheets must match the compiler: set TW_VERSION = "${tag[1]}" and ` +
        `re-run \`moon run --target native cmd/dev -- css-bundle\`.`,
    );
  }
  console.log(`tailwind pin matches the ported compiler (v${version})`);
}

/// Ensure _build/tailwind/tw holds Tailwind's theme/preflight/utilities at
/// `version`, downloading the npm tarball when missing or at a different
/// version. Returns the checkout path (the entry's `--base`).
export async function ensureTailwind({ version = TW_VERSION, force = false } = {}) {
  checkPin({ version });
  if (
    !force &&
    existsSync(STAMP) &&
    readFileSync(STAMP, "utf8").trim() === version &&
    FILES.every((f) => existsSync(join(TW_DIR, f)))
  ) {
    console.log(`tailwindcss ${version} already at _build/tailwind/tw`);
    return TARGET;
  }
  const url = `https://registry.npmjs.org/tailwindcss/-/tailwindcss-${version}.tgz`;
  console.log(`downloading ${url} → _build/tailwind/tw`);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`GET ${url} failed: ${res.status} ${res.statusText}`);
  }
  rmSync(TARGET, { recursive: true, force: true });
  mkdirSync(TW_DIR, { recursive: true });
  const tgz = join(TARGET, "tailwindcss.tgz");
  writeFileSync(tgz, Buffer.from(await res.arrayBuffer()));
  // Only the three CSS files, flattened out of the tarball's package/ prefix.
  // Shelling out to tar keeps this dependency-free, the same way the margaui
  // fetch shells out to git.
  execFileSync(
    "tar",
    ["-xzf", tgz, "-C", TW_DIR, "--strip-components=1", ...FILES.map((f) => `package/${f}`)],
    { stdio: "inherit" },
  );
  rmSync(tgz, { force: true });
  for (const f of FILES) {
    if (!existsSync(join(TW_DIR, f))) {
      throw new Error(`tailwindcss-${version}.tgz did not contain package/${f}`);
    }
  }
  writeFileSync(STAMP, `${version}\n`);
  return TARGET;
}

// CLI entry point.
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const at = argv.indexOf("--version");
  if (at !== -1 && at + 1 >= argv.length) {
    console.error("error: --version requires a value");
    process.exit(2);
  }
  try {
    await ensureTailwind({
      version: at === -1 ? TW_VERSION : argv[at + 1],
      force: argv.includes("--force"),
    });
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}
