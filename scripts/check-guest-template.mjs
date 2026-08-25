// Compile-check the guest tree `tutuca new-guest` writes out.
//
// The template ships INSIDE the CLI binary (cli/guest_template_gen.mbt), and it
// is the first thing anyone writing a `tutuca:component` guest sees. Nothing
// else covers it: `ci` never builds a guest — `guests` is a separate task
// needing wasm-tools and jco — and the template is assembled from three sources
// (the checked-in bindings of guests/counter, the ONE WIT, and the overlay in
// guests/template/) with placeholders substituted at write time, so all three
// can be individually fine and the result still not compile.
//
// This runs the real binary and compiles the real output, and needs only `moon`
// and `node` — no wit-bindgen, no wasm-tools, no jco — which is why it can be
// part of `ci` when `guests` cannot.
//
// It deliberately scaffolds under a name that is NOT one of the repo's guests,
// so a template that leaked a `counter` path fails here rather than in someone
// else's directory.
//
// Run:
//   moon run --target native cmd/dev -- guest-template-embed
//   moon build --target native cmd/tutuca
//   node scripts/check-guest-template.mjs
import { rmSync, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const BIN = join(REPO, "_build/native/debug/build/cmd/tutuca/tutuca.exe");
const OUT = join(REPO, "_build/guest-template-check");
// Two words, so it exercises the kebab -> PascalCase/snake_case split that a
// one-word name would let slide.
const NAME = "smoke-check";

if (!existsSync(BIN)) {
  console.error(
    `check-guest-template: no CLI binary at ${BIN}\n` +
      "  build it first: moon build --target native cmd/tutuca",
  );
  process.exit(2);
}

rmSync(OUT, { recursive: true, force: true });

try {
  execFileSync(BIN, ["new-guest", NAME, "--dir", OUT, "--force"], {
    stdio: "pipe",
    cwd: REPO,
  });
} catch (e) {
  const err = (e.stderr ?? Buffer.from("")).toString();
  if (err.includes("ERR_GUEST_TEMPLATE_MISSING")) {
    console.error(
      "check-guest-template: this binary has no embedded template.\n" +
        "  regenerate and rebuild:\n" +
        "    moon run --target native cmd/dev -- guest-template-embed\n" +
        "    moon build --target native cmd/tutuca",
    );
    process.exit(1);
  }
  console.error(`check-guest-template: new-guest failed\n${err}`);
  process.exit(1);
}

// Every file: no placeholder may survive, and nothing may still name the guest
// the template was derived from.
function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === "_build" || entry === "dist" || entry === "node_modules") continue;
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}

let bad = 0;
for (const path of walk(OUT)) {
  const rel = path.slice(OUT.length + 1);
  if (rel.includes("counter")) {
    console.error(`✗ ${rel}: a path from the source guest leaked into the template`);
    bad++;
    continue;
  }
  if (path.endsWith(".wasm")) continue;
  const text = readFileSync(path, "utf8");
  if (text.includes("{{")) {
    console.error(`✗ ${rel}: an unsubstituted {{placeholder}} survived`);
    bad++;
  }
}
if (bad) {
  console.error(`check-guest-template: ${bad} problem(s) in the scaffolded tree`);
  process.exit(1);
}

// The check that matters: does what a stranger gets actually compile?
//
// --deny-warn, and not as a stylistic preference. The failure this check was
// written to catch is a WARNING: name a guest `smoke-test` and its source
// becomes `smoke_test.mbt`, which MoonBit reads as a test file, so the author's
// `dyn_module` lands in test scope and the bundle declares nothing. `moon check`
// says "declaration not implemented" and exits 0. A scaffold that emits a
// warning is a scaffold that teaches someone to ignore warnings on day one.
try {
  execFileSync("moon", ["check", "--target", "wasm", "--deny-warn"], {
    stdio: "inherit",
    cwd: OUT,
  });
} catch {
  console.error(
    `check-guest-template: the scaffolded guest does not compile cleanly (${OUT})\n` +
      "  the tree is left in place — cd there and run `moon check --target wasm`",
  );
  process.exit(1);
}

console.log(`check-guest-template: '${NAME}' scaffolds and compiles`);
rmSync(OUT, { recursive: true, force: true });
