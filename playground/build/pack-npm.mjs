// Stage and pack the playground's two npm packages from an assembled dist/.
//
//   @marianoguerra/tutuca-playground          the shell: element, worker,
//                                             editor, view generator, margaui
//   @marianoguerra/tutuca-playground-payload  manifest.json + fs/ (the .mi/.core
//                                             bundles user code compiles against)
//
// Two packages because they are different kinds of thing: the shell is a few
// hundred KB versioned with tutuca, the payload is ~22 MB of build output that
// has to be regenerated whenever the MoonBit toolchain moves. They unpack into
// the SAME relative layout (playground/ + site/), so a consumer copying both
// into a static directory gets the folder arrangement everything resolves
// against by default — no configuration, no duplication.
//
// What is deliberately NOT packed: moonc-web.cjs. It is upstream's
// @moonbit/moonc-worker build, published with no license field, and the
// playground can be pointed at a consumer's own copy (MB_PLAYGROUND.compilerUrl)
// — so the payload names the exact version in peerDependencies instead of
// redistributing 5.5 MB of someone else's compiler.
//
// This PACKS ONLY. Publishing stays a deliberate manual step; the script prints
// the commands. Run after `cmd/dev -- dist` (or `-- playground` plus
// `assemble-site.mjs`):
//
//   node playground/build/pack-npm.mjs
import { readFileSync, writeFileSync, mkdirSync, rmSync, cpSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DIST = join(REPO, "dist/playground");
const SITE = join(REPO, "dist/site");
const SRC = join(REPO, "playground/npm");
const OUT = join(REPO, "_build/npm");

// The version is moon.mod's, for BOTH packages: the payload carries tutuca's own
// .mi/.core, so it turns over on a library release exactly as the shell does.
// (What the toolchain pins is recorded in manifest.json and in the payload's
// peerDependencies, not in the version number.)
const moonMod = readFileSync(join(REPO, "moon.mod"), "utf8");
const version = /^\s*version\s*=\s*"([^"]+)"/m.exec(moonMod)?.[1];
if (!version) throw new Error("no version in moon.mod");
const TOOLCHAIN = JSON.parse(readFileSync(join(REPO, "playground/build/toolchain.json"), "utf8"));

if (!existsSync(join(DIST, "manifest.json")) || !existsSync(join(SITE, "embed.js"))) {
  console.error("dist is not assembled — run: moon run --target native cmd/dev -- dist");
  process.exit(1);
}

// The publish gate. assemble.mjs already refuses to build against a toolchain
// that isn't the pinned one, so this catches the other direction: a dist/ left
// over from before a pin bump, which would ship bundles the payload's
// peerDependency then misdescribes.
const manifest = JSON.parse(readFileSync(join(DIST, "manifest.json"), "utf8"));
if (manifest.toolchain !== TOOLCHAIN.moonc || manifest.mooncWorker !== TOOLCHAIN.mooncWorker) {
  console.error(
    `stale dist: dist/playground/manifest.json was assembled against moonc ${manifest.toolchain} ` +
      `/ moonc-worker ${manifest.mooncWorker}, but playground/build/toolchain.json now pins ` +
      `${TOOLCHAIN.moonc} / ${TOOLCHAIN.mooncWorker}. Re-run the dist build.`,
  );
  process.exit(1);
}

// The shell's runtime files. moonc-web.cjs, manifest.json and fs/ are the other
// two packages' business (see the header).
const SHELL = [
  "runtime.js",
  "compiler.worker.js",
  "viewgen-client.js",
  "driver.js",
  "starter.js",
  "index.html",
  "editor.bundle.js",
  "viewgen.js",
  "margaui.wasm",
];

function stage(name, fill) {
  const dir = join(OUT, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const pkg = JSON.parse(readFileSync(join(SRC, name, "package.json"), "utf8"));
  pkg.version = version;
  fill(dir, pkg);
  writeFileSync(join(dir, "package.json"), JSON.stringify(pkg, null, 2) + "\n");
  cpSync(join(SRC, name, "README.md"), join(dir, "README.md"));
  cpSync(join(REPO, "LICENSE"), join(dir, "LICENSE"));
  // npm pack prints the tarball name on stdout; keep the tarballs beside the
  // staged trees so both can be inspected before anyone publishes.
  const tgz = execSync(`npm pack --pack-destination "${OUT}"`, { cwd: dir, encoding: "utf8" })
    .trim()
    .split("\n")
    .pop();
  return { name: pkg.name, tgz: join(OUT, tgz) };
}

const packed = [
  stage("playground", (dir) => {
    mkdirSync(join(dir, "playground"), { recursive: true });
    mkdirSync(join(dir, "site"), { recursive: true });
    for (const f of SHELL) cpSync(join(DIST, f), join(dir, "playground", f));
    cpSync(join(SITE, "embed.js"), join(dir, "site/embed.js"));
  }),
  stage("payload", (dir, pkg) => {
    // The pair the payload was built with, named exactly: npm then refuses to
    // resolve a compiler that cannot read these bundles.
    pkg.peerDependencies["@moonbit/moonc-worker"] = TOOLCHAIN.mooncWorker;
    // …and the whole pin, so `npm view` answers what a bundle was built from.
    pkg.moonbit = {
      moonc: TOOLCHAIN.moonc,
      mooncBuild: TOOLCHAIN.mooncBuild,
      moon: TOOLCHAIN.moon,
      mooncWorker: TOOLCHAIN.mooncWorker,
    };
    mkdirSync(join(dir, "playground"), { recursive: true });
    cpSync(join(DIST, "manifest.json"), join(dir, "playground/manifest.json"));
    cpSync(join(DIST, "fs"), join(dir, "playground/fs"), { recursive: true });
  }),
];

console.log(`\npacked v${version} -> _build/npm/`);
for (const p of packed) console.log(`  ${p.name}  ${p.tgz.slice(REPO.length + 1)}`);
console.log(
  "\nInspect a tarball with `tar tzf <file>`, then publish (scoped packages are\n" +
    "private by default, so the first release of each needs --access public):\n" +
    packed.map((p) => `  npm publish ${p.tgz.slice(REPO.length + 1)} --access public`).join("\n"),
);
