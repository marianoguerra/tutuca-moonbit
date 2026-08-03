// Shared facts about the MoonBit `tutuca:component` guests: where they live
// and which WIT they implement. Both the builder (build-guest.mjs) and the
// binding generator (gen-bindings.mjs) read them from here, so "which WIT"
// has exactly one answer.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

///  The MoonBit guests. The Rust guest (guests/rust-tempconv) implements the
///  same WIT but builds through cargo, so it keeps its own script.
export const GUESTS = ['counter', 'table', 'todo', 'todomvc', 'calculator', 'tictactoe'];

export const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

/// The ONE WIT source in the repo. Guests do not keep a copy: wasm-tools
/// embeds this directory directly, wit-bindgen generates from it, and the
/// Rust guest's `generate!` macro points at it — so a guest cannot silently
/// implement a different contract than dyncomp/host expects.
export const WIT_DIR = join(repoRoot, 'dyncomp', 'wit');

export const guestDir = (name) => join(repoRoot, 'guests', name);

/// The ONE SDK source, for the same reason there is one WIT: it used to be five
/// byte-identical copies, and five copies of a contract is five chances to
/// answer "what does a guest implement" differently. gen-bindings.mjs copies it
/// into every guest tree, and `tutuca new-guest` emits it into a new one.
export const SDK_SRC = join(repoRoot, 'guests', 'sdk.mbt');

/// The ONE table codec, copied the same way and for the same reason.
///
/// It is separate from the SDK because it answers a different question: the SDK
/// implements the guest's side of the ABI, this converts between the arena
/// `values.value` a table arrives as and the `tables.*` types the contract
/// declares. A guest that never touches a table still compiles with it — it is
/// plain functions, no `declare` — so there is no cost to shipping it always,
/// and a guest that DOES want a table should not have to write the conversion.
export const TABLES_SRC = join(repoRoot, 'guests', 'tables.mbt');

/// jco's entry point, from the repo's own node_modules — never from PATH, where
/// the bare "jco" name is a dependency-confusion placeholder. Ask jco's manifest
/// where the entry point is rather than hard-coding it: 1.25 shipped
/// `src/jco.js` and 1.26 moved it to `dist/jco.js`, so a path written out here
/// breaks on the next release of a dependency package.json declares with a
/// caret. `guests/template` and the dice example resolve their own copies the
/// same way.
export const jcoBin = () => {
  const pkg = join(repoRoot, 'node_modules', '@bytecodealliance', 'jco', 'package.json');
  if (!existsSync(pkg)) {
    console.error('jco is not installed — run `npm install` in the repo root first');
    process.exit(1);
  }
  const bin = JSON.parse(readFileSync(pkg, 'utf8')).bin;
  const entry = join(dirname(pkg), typeof bin === 'string' ? bin : bin.jco);
  if (!existsSync(entry)) {
    console.error(`jco's manifest points at ${entry}, which is not there — reinstall it`);
    process.exit(1);
  }
  return entry;
};

/// Where a guest's copy of the SDK lives: beside the wit-bindgen output it
/// implements, because a `declare` can only be implemented in its own package.
export const sdkDest = (name) =>
  join(guestDir(name), 'gen', 'interface', 'tutuca', 'component', 'guest', 'sdk.mbt');

/// The table codec's copy, beside the SDK: it reaches for both `@values` and
/// `@tables`, and this package is where the guest already imports the first.
export const tablesDest = (name) =>
  join(guestDir(name), 'gen', 'interface', 'tutuca', 'component', 'guest', 'tables.mbt');
