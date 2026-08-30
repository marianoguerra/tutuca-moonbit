// Hold `@cli.MODULE_VERSION` against `version` in moon.mod.
//
// `tutuca new-storybook` writes a `moon.mod` that pins `marianoguerra/tutuca`
// at this number, and the scaffold is compiled INTO the binary — so a stale
// constant hands a new user a project that resolves to the wrong release, or
// to one that predates the packages the scaffold imports. Nothing else notices:
// it is a string in a MoonBit file, and every test that reads it reads the same
// string.
//
// Run:
//   node scripts/check-module-version.mjs
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const mod = readFileSync(join(REPO, "moon.mod"), "utf8");
const cli = readFileSync(join(REPO, "cli/version.mbt"), "utf8");

const modVersion = mod.match(/^\s*version\s*=\s*"([^"]+)"/m)?.[1];
const cliVersion = cli.match(/MODULE_VERSION\s*:\s*String\s*=\s*"([^"]+)"/)?.[1];

if (!modVersion) {
  console.error("check-module-version: no `version` in moon.mod");
  process.exit(2);
}
if (!cliVersion) {
  console.error("check-module-version: no `MODULE_VERSION` in cli/version.mbt");
  process.exit(2);
}
if (modVersion !== cliVersion) {
  console.error(
    `check-module-version: moon.mod says ${modVersion}, cli/version.mbt says ${cliVersion}\n` +
      "  update MODULE_VERSION in cli/version.mbt (the scaffold pins it)",
  );
  process.exit(1);
}
console.log(`check-module-version: ok (${modVersion})`);
