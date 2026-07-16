// Assemble the landing site into dist/ : the marketing/gallery page that embeds
// live <mb-playground> elements. Reuses the compiler payload already assembled
// into dist/playground/ (by assemble.mjs) — the embed element points its worker
// at ./playground/compiler.worker.js, so nothing here is duplicated.
//
// Layout produced:
//   dist/index.html          ← the landing page (site becomes the dist root)
//   dist/styles/site.css      ← page styling (self-contained light/dark palette)
//   dist/site/embed.js        ← the <mb-playground> custom element
//   dist/site/examples/*.mbt  ← the editable example sources
//
// Prereq: assemble.mjs has run (dist/playground/ exists). Run:
//   node playground/build/assemble-site.mjs
import { mkdirSync, rmSync, readdirSync, cpSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SITE = join(REPO, "playground/site");
const DIST = join(REPO, "dist");

// the landing page is the dist root
cpSync(join(SITE, "index.html"), join(DIST, "index.html"));

// page styles
mkdirSync(join(DIST, "styles"), { recursive: true });
cpSync(join(SITE, "styles"), join(DIST, "styles"), { recursive: true });

// the embeddable element + its example sources under dist/site/
const outSite = join(DIST, "site");
rmSync(outSite, { recursive: true, force: true });
mkdirSync(join(outSite, "examples"), { recursive: true });
cpSync(join(SITE, "embed.js"), join(outSite, "embed.js"));
cpSync(join(SITE, "examples"), join(outSite, "examples"), { recursive: true });

const examples = readdirSync(join(SITE, "examples")).filter((f) => f.endsWith(".mbt"));
console.log(`done -> ${DIST}\n  index.html + styles/ + site/embed.js + ${examples.length} examples`);
