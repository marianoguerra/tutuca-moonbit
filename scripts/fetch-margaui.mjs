// Fetch the margaui checkout that the `margaui-bundle` dev task resolves
// demo/assets/margaui.entry.css's `@import`s against, into the gitignored
// _build/margaui/. Nothing in the repo depends on a sibling ../margaui working
// copy any more: the source of truth is the pinned tag below, cloned from
// GitHub on demand (shallow, ~6 MB) and thrown away with the rest of _build/.
//
// The pin is what makes the regen reproducible — the committed
// demo/assets/margaui.bundle.json + demo/margaui/bundle_gen.mbt are exactly
// what this ref produces. To pick up new margaui CSS: bump MARGAUI_REF, re-run
// `moon run --target native cmd/dev -- margaui-bundle`, and commit the pin
// together with the regenerated bundle.
//
// Run directly:  node scripts/fetch-margaui.mjs [--ref <tag>] [--force]
// Or import:     import { ensureMargaui } from "./fetch-margaui.mjs"
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// The margaui release the committed bundle was generated from.
export const MARGAUI_REF = "v0.5606.3";
export const MARGAUI_REPO = "https://github.com/marianoguerra/margaui.git";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TARGET = join(ROOT, "_build/margaui");
// Records which ref TARGET holds. A shallow clone checks out a detached HEAD,
// so there is nothing in .git to read the requested ref back from; this stamp
// is what makes a re-run with a bumped MARGAUI_REF re-clone instead of reuse.
const STAMP = join(TARGET, ".tutuca-margaui-ref");

/// Ensure _build/margaui holds a margaui checkout at `ref`, cloning it when
/// missing or at a different ref. Returns the checkout path.
export function ensureMargaui({ ref = MARGAUI_REF, force = false } = {}) {
  if (!force && existsSync(STAMP) && readFileSync(STAMP, "utf8").trim() === ref) {
    console.log(`margaui ${ref} already at _build/margaui`);
    return TARGET;
  }
  console.log(`cloning margaui ${ref} → _build/margaui`);
  rmSync(TARGET, { recursive: true, force: true });
  mkdirSync(dirname(TARGET), { recursive: true });
  // --branch takes a tag as well as a branch; --depth 1 skips the history we
  // have no use for (we only ever read the CSS tree at one ref). Checking a tag
  // out lands on a detached HEAD, whose ten-line advice block is noise here.
  execFileSync(
    "git",
    [
      "-c", "advice.detachedHead=false",
      "clone", "--quiet", "--depth", "1", "--branch", ref, MARGAUI_REPO, TARGET,
    ],
    { stdio: "inherit" },
  );
  writeFileSync(STAMP, `${ref}\n`);
  return TARGET;
}

// CLI entry point.
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const at = argv.indexOf("--ref");
  if (at !== -1 && at + 1 >= argv.length) {
    console.error("error: --ref requires a value");
    process.exit(2);
  }
  ensureMargaui({
    ref: at === -1 ? MARGAUI_REF : argv[at + 1],
    force: argv.includes("--force"),
  });
}
