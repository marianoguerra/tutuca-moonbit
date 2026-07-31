// Shared facts about the MoonBit `tutuca:component` guests: where they live
// and which WIT they implement. Both the builder (build-guest.mjs) and the
// binding generator (gen-bindings.mjs) read them from here, so "which WIT"
// has exactly one answer.
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

///  The MoonBit guests. The Rust guest (guests/rust-notepad) implements the
///  same WIT but builds through cargo, so it keeps its own script.
export const GUESTS = ['counter', 'todo', 'todomvc'];

export const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

/// The ONE WIT source in the repo. Guests do not keep a copy: wasm-tools
/// embeds this directory directly, wit-bindgen generates from it, and the
/// Rust guest's `generate!` macro points at it — so a guest cannot silently
/// implement a different contract than dyncomp/host expects.
export const WIT_DIR = join(repoRoot, 'dyncomp', 'wit');

export const guestDir = (name) => join(repoRoot, 'guests', name);
