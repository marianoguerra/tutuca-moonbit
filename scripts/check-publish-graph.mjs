// Hold the published package graph closed: no package that ships may import one
// that does not.
//
// `moon.mod`'s `options(exclude: [...])` decides what stays out of the tarball.
// Nothing enforces the other half — that what DOES ship can still resolve every
// name it imports — and the failure is invisible here: the excluded package is
// sitting in the working tree, so `moon check` is happy and only a consumer who
// unpacked the archive ever sees the break.
//
// `for "test"` blocks count. A `*_test.mbt` file and its imports survive
// `moon publish` (unpack any tarball under a project's `.mooncakes` and look),
// so a shipping package that test-imports an excluded one poisons the graph
// exactly as a main import would.
//
// Run:
//   node scripts/check-publish-graph.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const MOD = readFileSync(join(REPO, "moon.mod"), "utf8");

const NAME = MOD.match(/^\s*name\s*=\s*"([^"]+)"/m)?.[1];
if (!NAME) {
  console.error("check-publish-graph: no `name` in moon.mod");
  process.exit(2);
}

// options(exclude: [ "a", "b/c", ... ])
const excludeBlock = MOD.match(/exclude:\s*\[([\s\S]*?)\]/)?.[1];
if (!excludeBlock) {
  console.error("check-publish-graph: no `options(exclude: [...])` in moon.mod");
  process.exit(2);
}
const excluded = [...excludeBlock.matchAll(/"([^"]+)"/g)].map((m) => m[1]);

/** Is this repo-relative package path excluded from the archive? */
const isExcluded = (pkg) =>
  excluded.some((e) => pkg === e || pkg.startsWith(e + "/"));

/** Every directory holding a moon.pkg, minus nested modules and build output. */
function packages(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const name = entry.name;
    if (name === "_build" || name === ".mooncakes" || name === ".git") continue;
    if (name === "node_modules" || name === "target" || name === "dist") continue;
    const sub = join(dir, name);
    // a nested moon.mod is a separate module (examples/*): moon's own
    // discovery stops there, so this does too
    if (existsFile(join(sub, "moon.mod")) || existsFile(join(sub, "moon.mod.json"))) {
      continue;
    }
    if (existsFile(join(sub, "moon.pkg")) || existsFile(join(sub, "moon.pkg.json"))) {
      out.push(relative(REPO, sub).split(sep).join("/"));
    }
    packages(sub, out);
  }
  return out;
}

function existsFile(p) {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

/** Every `marianoguerra/tutuca/...` import in a moon.pkg, main and test alike. */
function importsOf(pkgDir) {
  const file = ["moon.pkg", "moon.pkg.json"]
    .map((n) => join(REPO, pkgDir, n))
    .find(existsFile);
  const src = readFileSync(file, "utf8");
  // strip line comments so a commented-out import is not a finding
  const code = src.replace(/^\s*\/\/.*$/gm, "");
  return [...code.matchAll(new RegExp(`"${NAME}/([^"]+)"`, "g"))].map((m) => m[1]);
}

const bad = [];
for (const pkg of packages(REPO).sort()) {
  if (isExcluded(pkg)) continue;
  for (const imp of importsOf(pkg)) {
    if (isExcluded(imp)) bad.push({ pkg, imp });
  }
}

if (bad.length > 0) {
  console.error("check-publish-graph: shipping packages import excluded ones\n");
  for (const { pkg, imp } of bad) {
    console.error(`  ${pkg}  ->  ${imp}`);
  }
  console.error(
    "\nEither the importer belongs in moon.mod's exclude list, or the imported\n" +
      "package has to ship. A `for \"test\"` import counts: test files are in the\n" +
      "tarball too.",
  );
  process.exit(1);
}

console.log(
  `check-publish-graph: ok (${excluded.length} excluded paths, no shipping package reaches them)`,
);
