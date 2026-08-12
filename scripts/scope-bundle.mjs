// Copy a moonc js bundle into a page's folder with a scope of its own.
//
// moonc's js output declares everything at TOP LEVEL — `function _M0…`, `const
// _M0…` — and wraps only the entry-point call in an IIFE. A classic <script>
// puts those declarations in the page's global lexical scope, so two moonc
// bundles on one page collide on every symbol they share, and both linking
// moonbitlang/core is enough to share hundreds. The second one to evaluate
// dies with `redeclaration of const …` before it runs a line — and a script
// that fails to PARSE still fires `load`, so the page sees a bundle that
// loaded and published nothing.
//
// The landing site is exactly that page: `site/tutucard.js` (classic, in the
// head) and `playground/viewgen.js` (injected on demand by viewgen-client.js),
// with the second silently dead and every View tab reporting "viewgen.js
// loaded but published no generator". Wrapping a bundle in a function keeps
// its declarations to itself; the entry point still runs on load and still
// publishes its one global (`__tutucard`, `__tutucaViewgen`).
import { readFileSync, writeFileSync } from "node:fs";

/**
 * Write `src` to `dest` wrapped in a function scope.
 *
 * @param {string} src  a moonc js bundle
 * @param {string} dest where the page loads it from
 */
export function copyScoped(src, dest) {
  const js = readFileSync(src, "utf8");
  // The newline before the closing brace matters: the bundle ends in a
  // `//# sourceMappingURL` line comment, which would otherwise swallow it.
  writeFileSync(dest, `(() => {\n${js}\n})();\n`);
}
