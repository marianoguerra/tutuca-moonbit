// Build every guest bundle, then run the node harnesses over them.
//
// The harnesses in `dyncomp/test/` are the only RUNTIME coverage the guest ABI
// has: `moon test` never loads a component (that needs wasm-tools and jco to
// produce one), so everything below the WIT — the arena encoding, the tar
// reader, the table codec, the Rust guest implementing the same contract — is
// exercised here or nowhere. Their only invocation instruction used to be a
// sentence in CONTRIBUTING.md.
//
// A script rather than more steps in the task because building N guests and
// then running the harnesses is one job with a shared failure mode: a harness
// that cannot find `guests/<name>/dist/js` has not failed, it has not been
// given anything to test, and saying which is the whole point.
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { GUESTS, guestDir } from "../guests/guests.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const RUST_GUEST = "rust-tempconv";

const run = (cmd, args) =>
  execFileSync(cmd, args, { cwd: REPO, stdio: "inherit" });

for (const name of GUESTS) {
  console.log(`\n── building ${name} ──`);
  run("node", ["guests/build-guest.mjs", name]);
}
console.log(`\n── building ${RUST_GUEST} (cargo) ──`);
run("node", [`guests/${RUST_GUEST}/build.mjs`]);

// Every harness reads a built bundle; say so plainly rather than letting
// node:test report a file-not-found from inside a test body.
const missing = [...GUESTS, RUST_GUEST].filter(
  (n) => !existsSync(join(guestDir(n), "dist", "js")),
);
if (missing.length > 0) {
  console.error(
    `these guests built without producing dist/js, so the harnesses have ` +
      `nothing to run against: ${missing.join(", ")}`,
  );
  process.exit(1);
}

console.log("\n── harnesses ──");
run("node", ["--test", "dyncomp/test/"]);
