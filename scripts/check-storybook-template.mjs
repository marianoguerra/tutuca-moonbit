// Check the gallery project `tutuca new-storybook` writes out.
//
// It is what someone building their first storybook sees, it lives INSIDE the
// binary (cli/storybook_template_gen.mbt), and nothing else looks at it.
//
// Structural only, and not out of laziness: this project depends on the
// PUBLISHED `marianoguerra/tutuca` — which will not contain the packages its
// page imports until the release that adds them — so the compile check belongs
// to `examples/`, run after a release.
// What is checkable here is everything that can be wrong without a compiler:
//
//   1. no placeholder survived substitution
//   2. the wasm-gc `link.exports` list and the page's `pub fn`s agree — an
//      export naming a function that does not exist fails the LINK, long after
//      this, and a `pub fn` missing from the list is worse: it builds, and the
//      page calls an export that is not there
//   3. every relative module index.html imports is one build.mjs writes
//   4. the pinned tutuca version is this build's MODULE_VERSION
//
// Run:
//   moon run --target native cmd/dev -- storybook-template-embed
//   moon build --target native cmd/tutuca
//   node scripts/check-storybook-template.mjs
import { rmSync, existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const BIN = join(REPO, "_build/native/debug/build/cmd/tutuca/tutuca.exe");
const OUT = join(REPO, "_build/storybook-template-check");
// Two words, so the kebab split is exercised rather than let slide.
const NAME = "smoke-gallery";

if (!existsSync(BIN)) {
  console.error(
    `check-storybook-template: no CLI binary at ${BIN}\n` +
      "  build it first: moon build --target native cmd/tutuca",
  );
  process.exit(2);
}

rmSync(OUT, { recursive: true, force: true });
execFileSync(BIN, ["new-storybook", NAME, "--dir", OUT], { stdio: "inherit" });

const fail = [];
const read = (rel) => readFileSync(join(OUT, rel), "utf8");

// --- 1. nothing left to substitute ----------------------------------------

const files = [
  "moon.mod",
  "README.md",
  "index.html",
  "build.mjs",
  ".gitignore",
  "page/moon.pkg",
  "page/main.mbt",
  "page/counter.html",
  "page/counter_view_gen.mbt",
];
for (const rel of files) {
  if (!existsSync(join(OUT, rel))) {
    fail.push(`  missing: ${rel}`);
    continue;
  }
  if (read(rel).includes("{{")) {
    fail.push(`  ${rel}: an unsubstituted {{placeholder}} survived`);
  }
}
if (fail.length > 0) {
  console.error("check-storybook-template: the scaffold is incomplete\n");
  console.error(fail.join("\n"));
  process.exit(1);
}

// --- 2. exports vs the page's public functions ----------------------------

const pkg = read("page/moon.pkg");
const exportsBlock = pkg.match(/"exports"\s*:\s*\[([\s\S]*?)\]/)?.[1] ?? "";
const exported = [...exportsBlock.matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
const main = read("page/main.mbt");
const pubFns = [...main.matchAll(/^pub fn (\w+)\s*\(/gm)].map((m) => m[1]).sort();
// Every export must exist (an export with no function fails the LINK, long
// after this), and the five entry points the page calls must all be exported (a
// missing one builds fine and the page calls something that is not there). Not
// an equality: a project's own `pub fn`s — the modules it shows — are not
// entry points, and the template ships one.
const ENTRY_POINTS = [
  "mount",
  "on_event",
  "on_fuzz_tick",
  "on_popstate",
  "refresh_margaui",
];
for (const name of exported) {
  if (!pubFns.includes(name)) {
    fail.push(`  page/moon.pkg exports "${name}", which page/main.mbt does not define`);
  }
}
for (const name of ENTRY_POINTS) {
  if (!exported.includes(name)) {
    fail.push(`  page/moon.pkg does not export "${name}", which index.html calls`);
  }
}

// --- 3. what index.html imports vs what build.mjs writes ------------------

const build = read("build.mjs");
const written = new Set(
  [...build.matchAll(/join\(dist,\s*"([^"]+)"\)/g)].map((m) => m[1]),
);
const html = read("index.html");
const SPECIFIER = /(?:\bfrom\s*|\bimport\s*\(\s*)["'](\.\/[^"']*)["']/g;
for (const [, spec] of html.matchAll(SPECIFIER)) {
  const name = spec.replace(/^\.\//, "");
  if (!written.has(name)) {
    fail.push(`  index.html imports "${spec}", which build.mjs never writes`);
  }
}
// the page module itself is loaded by URL rather than imported
for (const [, url] of html.matchAll(/instantiate\(\s*"\.\/([^"]+)"/g)) {
  if (!written.has(url)) {
    fail.push(`  index.html loads "./${url}", which build.mjs never writes`);
  }
}

// --- 4. the pinned version is this build's ---------------------------------

const pinned = read("moon.mod").match(/"marianoguerra\/tutuca@([^"]+)"/)?.[1];
const moduleVersion = readFileSync(join(REPO, "cli/version.mbt"), "utf8").match(
  /MODULE_VERSION\s*:\s*String\s*=\s*"([^"]+)"/,
)?.[1];
if (pinned !== moduleVersion) {
  fail.push(
    `  moon.mod pins marianoguerra/tutuca@${pinned}, MODULE_VERSION is ${moduleVersion}`,
  );
}

if (fail.length > 0) {
  console.error("check-storybook-template: the scaffolded project is wrong\n");
  console.error(fail.join("\n"));
  process.exit(1);
}

rmSync(OUT, { recursive: true, force: true });
console.log(
  `check-storybook-template: ok (${files.length} files, ${exported.length} exports, pinned @${pinned})`,
);
