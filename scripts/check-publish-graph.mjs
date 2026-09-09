import { spawnSync } from "node:child_process";
// Check the actual package inventory, including root and test imports.
import { readFileSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const MOD = readFileSync(join(REPO, "moon.mod"), "utf8");
const NAME = MOD.match(/^\s*name\s*=\s*"([^"]+)"/m)?.[1];
if (!NAME) throw Error("set the module name in moon.mod");
const listed = spawnSync("moon", ["package", "--list"], { cwd: REPO, encoding: "utf8" });
if (listed.status !== 0) {
  process.stderr.write(listed.stdout + listed.stderr);
  process.exit(listed.status ?? 1);
}
const inventory = new Set((listed.stdout + "\n" + listed.stderr).split("\n").map(l => l.trim()).filter(l => existsFile(join(REPO, l))));
const shipping = new Set([...inventory].filter(p => /(^|\/)moon\.pkg(?:\.json)?$/.test(p)).map(p => dirname(p) === "." ? "" : dirname(p)));
if (!shipping.has("")) throw Error("moon package --list did not include the root package");
function existsFile(path) {
  try { return statSync(path).isFile(); } catch { return false; }
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
for (const pkg of [...shipping].sort()) {
  for (const imp of importsOf(pkg)) {
    if (!shipping.has(imp)) bad.push({ pkg, imp });
  }
}

if (bad.length > 0) {
  console.error("check-publish-graph: shipping packages import excluded ones\n");
  for (const { pkg, imp } of bad) {
    console.error(`  ${pkg}  ->  ${imp}`);
  }
  console.error(
    "\nEither the importer belongs in .moonignore, or the imported\n" +
      "package has to ship. A `for \"test\"` import counts: test files are in the\n" +
      "tarball too.",
  );
  process.exit(1);
}

console.log(
  `check-publish-graph: ok (${shipping.size} shipping packages, all local imports included)`,
);
