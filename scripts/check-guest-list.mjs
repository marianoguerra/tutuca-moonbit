// The guest list exists twice and cannot exist once: `guests/guests.mjs` owns
// which names `build-guest.mjs` accepts (a fact about the script), and
// `dev/tasks.mbt` owns which bundles the build plans (a fact about the build,
// in a package that is deliberately I/O-free and so cannot read the first).
//
// Two lists is fine; two lists that disagree is not. `guests/table` sat in the
// first and not the second for long enough that nothing built it, nothing
// packed it, and its harness — the only runtime test of guests/tables.mbt —
// could not run. This is the check that says so.
//
// Usage: node scripts/check-guest-list.mjs <name>...
//   where <name>... is what dev/tasks.mbt's moonbit_guests() returns.
import { GUESTS } from '../guests/guests.mjs';

const planned = process.argv.slice(2);
const missing = GUESTS.filter((n) => !planned.includes(n));
const extra = planned.filter((n) => !GUESTS.includes(n));

if (missing.length === 0 && extra.length === 0) {
  console.log(`guest list agrees (${GUESTS.length}): ${GUESTS.join(', ')}`);
  process.exit(0);
}

console.error('guest list drift between guests/guests.mjs and dev/tasks.mbt:');
if (missing.length > 0) {
  console.error(
    `  in guests.mjs but NOT built by dev/tasks.mbt: ${missing.join(', ')}\n` +
      "    → add them to moonbit_guests() in dev/tasks.mbt",
  );
}
if (extra.length > 0) {
  console.error(
    `  built by dev/tasks.mbt but NOT in guests.mjs: ${extra.join(', ')}\n` +
      '    → add them to GUESTS in guests/guests.mjs, or drop them from moonbit_guests()',
  );
}
process.exit(1);
