#!/usr/bin/env node
// Fail on a string literal that MEANT to interpolate and did not.
//
// MoonBit interpolation is `\{expr}`. A bare `{expr}` is legal text, so a
// diagnostic that drops the backslash compiles, passes a suite that asserts
// codes, and prints `{d.name}` to an author who is trying to find out WHICH
// property is wrong. Six shipped that way in 0.49.5 — the entire
// property-checking family — and two consumers reported it before the repo's
// own tests could, because nothing asserted a message.
//
// The rule is a whole-repo ban with a named exemption list rather than a guess
// at which strings are diagnostics: "is this a message argument" needs a parser,
// and a heuristic that gets it wrong fails silently in the direction nobody
// notices. The legitimate uses are few, they are all template text, and each is
// written down below with the reason it is not a mistake.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

// Files whose `{…}` is text on purpose. Every entry is scaffold or embedded
// documentation: a placeholder some later `replace_all` substitutes, or tutuca's
// OWN template syntax quoted in prose.
const ALLOW = new Set([
  "cli/new_storybook.mbt",          // `{{name}}` scaffold slots
  "cli/storybook_template_gen.mbt", // embedded gallery template, same slots
  "cli/skill_assets_gen.mbt",       // embedded skill docs, quoting `$'{…}'`
]);

const SKIP = new Set([
  "node_modules",
  "dist",
  "_build",
  "target",
  ".git",
  // A fetched copy of a PUBLISHED tutuca. Its faults are already shipped and
  // are not this working tree to fix.
  ".mooncakes",
]);
// `\u{FFFD}` is an escape, not an interpolation.
const HIT = /(?<![\\u])\{([A-Za-z_][\w.]*(?:\([^)]*\))?)\}/g;

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    if (SKIP.has(e)) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (e.endsWith(".mbt")) out.push(p);
  }
  return out;
}

const bad = [];
for (const path of walk(".")) {
  const rel = path.replace(/^\.\//, "");
  if (ALLOW.has(rel)) continue;
  // Tests quote the view language freely (`$'{host.mediaOrigin}'`), and a test
  // cannot ship a bad diagnostic to anyone.
  if (/_(test|wbtest)\.mbt$/.test(rel)) continue;
  const lines = readFileSync(path, "utf8").split("\n");
  lines.forEach((line, i) => {
    if (!line.includes('"')) return;
    for (const m of line.matchAll(HIT)) {
      bad.push(`${rel}:${i + 1}: ${m[0]} — write \\${m[0]} to interpolate it`);
    }
  });
}

if (bad.length > 0) {
  console.error("uninterpolated `{…}` in a string literal:\n");
  for (const b of bad) console.error("  " + b);
  console.error(
    "\nMoonBit interpolation is `\\{expr}`. If the text is meant literally," +
      "\nadd the file to ALLOW in scripts/check-diagnostics.mjs with the reason.",
  );
  process.exit(1);
}
console.log(`ok: no uninterpolated placeholders (${ALLOW.size} files exempted)`);
