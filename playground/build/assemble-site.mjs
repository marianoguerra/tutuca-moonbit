// Assemble the landing site into dist/ : the marketing/gallery page that embeds
// live <mb-playground> elements. Reuses the compiler payload already assembled
// into dist/playground/ (by assemble.mjs) — the embed element points its worker
// at ./playground/compiler.worker.js, so nothing here is duplicated.
//
// It also embeds live <mb-card> elements, which need none of that: a card is
// parsed and mounted, so what the page loads for them is the tutuca runtime
// (dist/tutucard/tutucard.js, assembled by tutucard/build/assemble.mjs) and two
// small modules. Copied here rather than linked at ../tutucard/ so the landing
// page keeps working when the card playground is not part of a build.
//
// Layout produced:
//   dist/index.html           ← the landing page (site becomes the dist root)
//   dist/cards.html           ← the card tutorial, which is <mb-card> all the way down
//   dist/styles/site.css      ← page styling (self-contained light/dark palette)
//   dist/site/embed.js        ← the <mb-playground> custom element
//   dist/site/examples/*.mbt  ← the editable example sources
//   dist/site/card-embed.js   ← the <mb-card> custom element (+ regions.js)
//   dist/site/tutucard.js     ← the card runtime, which is the whole payload
//   dist/site/margaui.{js,wasm} ← the class compiler <mb-card margaui> fetches
//   dist/site/cards/*.html    ← the editable card sources
//
// Prereq: assemble.mjs and tutucard/build/assemble.mjs have run. Run:
//   node playground/build/assemble-site.mjs
import { existsSync, mkdirSync, rmSync, readdirSync, cpSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SITE = join(REPO, "playground/site");
const CARDWEB = join(REPO, "tutucard/web");
const DIST = join(REPO, "dist");

// The landing page is the dist root; every other page sits beside it, so the
// `./site/…` and `./styles/…` links in all of them mean the same thing.
const PAGES = ["index.html", "cards.html"];
for (const page of PAGES) {
  cpSync(join(SITE, page), join(DIST, page));
}

// page styles
mkdirSync(join(DIST, "styles"), { recursive: true });
cpSync(join(SITE, "styles"), join(DIST, "styles"), { recursive: true });

// the embeddable element + its example sources under dist/site/
const outSite = join(DIST, "site");
rmSync(outSite, { recursive: true, force: true });
mkdirSync(join(outSite, "examples"), { recursive: true });
cpSync(join(SITE, "embed.js"), join(outSite, "embed.js"));
cpSync(join(SITE, "examples"), join(outSite, "examples"), { recursive: true });

// The card half: the element, the one module it imports, the runtime, and the
// cards themselves.
cpSync(join(CARDWEB, "card-embed.js"), join(outSite, "card-embed.js"));
cpSync(join(CARDWEB, "regions.js"), join(outSite, "regions.js"));
cpSync(join(CARDWEB, "margaui.js"), join(outSite, "margaui.js"));
cpSync(join(SITE, "cards"), join(outSite, "cards"), { recursive: true });
// Two artifacts of the card build rather than of this one: the runtime every
// embed needs, and the margaui compiler an `<mb-card margaui>` fetches when it
// mounts. Missing rather than fatal — `dist` builds them before it gets here,
// but assembling the site alone is a thing people do while editing the page,
// and failing that with a build error about a folder they did not ask for
// helps nobody. The embeds say "runtime did not load" and the rest of the page
// works.
for (const [name, why] of [
  ["tutucard.js", "the <mb-card> embeds"],
  ["margaui.wasm", "an <mb-card margaui> to have any CSS"],
]) {
  const from = join(DIST, "tutucard", name);
  if (existsSync(from)) {
    cpSync(from, join(outSite, name));
  } else {
    console.warn(
      `  note: ${from} is missing — run the tutucard-playground task for ${why}`,
    );
  }
}

// The page links ./universal/ and ./dyncomp-storybook/, and neither is built by
// `dist`: both need the component toolchain (wasm-tools + jco) that CI does not
// have, so they are their own tasks. Say which task, rather than leaving a dead
// link to be found by clicking it.
for (const [dir, task] of [
  ["universal", "universal"],
  ["dyncomp-storybook", "dyncomp-storybook"],
]) {
  if (!existsSync(join(DIST, dir))) {
    console.warn(
      `  note: dist/${dir}/ is missing — the page links it; run the ${task} task to build it`,
    );
  }
}

const examples = readdirSync(join(SITE, "examples")).filter((f) => f.endsWith(".mbt"));
const cards = readdirSync(join(SITE, "cards")).filter((f) => f.endsWith(".html"));
console.log(
  `done -> ${DIST}\n  ${PAGES.join(" + ")} + styles/ + site/embed.js + ${examples.length} examples` +
    ` + site/card-embed.js + ${cards.length} card${cards.length === 1 ? "" : "s"}`,
);
