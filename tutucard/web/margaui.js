// margaui for cards: compile the class names a mounted card publishes, and
// scope the result to where that card is showing.
//
// The compiler half is the easy half and is not new — `margaui.wasm` is the
// same wasm-gc build of `@css.compile_margaui` that the other playground's
// `runtime.js` instantiates, with the same `compile(classesJson) -> css`
// export. What is new is the second half.
//
// **Why the CSS has to be scoped.** That playground mounts its preview in an
// IFRAME, so it can drop margaui's stylesheet into the preview's own document
// and be done. A card has no iframe: it mounts in the page's own DOM, beside
// the prose that introduces it (`card-embed.js` says why, and the host's
// `getElementById` requires it). And margaui's stylesheet is not a set of
// utilities you can sprinkle on a page — it carries Tailwind's PREFLIGHT
// (`*, ::before, ::after { margin: 0; padding: 0; border: 0 }`, `html`
// line-height, unstyled headings and lists) and a `:root` theme that paints
// the background. Injected as-is it does not style the card, it flattens the
// document around it.
//
// So every rule is rewritten to apply inside the preview only. The rewriting
// is done by the BROWSER's own parser — `CSSStyleSheet.replaceSync`, then a
// walk over `cssRules` — rather than by a regex over 60 KB of CSS with
// `@layer`, `@supports`, `@property` and nested at-rules in it. What the walk
// has to know is small and enumerated in `scopeSelector` below.

/** The compiled sheet, once per page. */
let compiling = null;

/**
 * Instantiate margaui.wasm and hand back its `compile`.
 *
 * Lazy and once: a page with no styled card never fetches the ~0.5 MB, and a
 * page with eight of them fetches it once. The instantiation options are the
 * ones moon's wasm-gc output needs — js-string builtins plus the imported
 * string constants it puts under module `_`.
 */
function compiler() {
  compiling ??= (async () => {
    const url = new URL("./margaui.wasm", import.meta.url);
    const bytes = await (await fetch(url)).arrayBuffer();
    const opts = { builtins: ["js-string"], importedStringConstants: "_" };
    const { instance } = await WebAssembly.instantiate(bytes, {}, opts);
    if (instance.exports._start) instance.exports._start();
    return (classesJson) => instance.exports.compile(classesJson);
  })();
  return compiling;
}

/** One accumulating sheet per style element id. */
const sheets = new Map();

/**
 * Add `classes` to the sheet identified by `styleId`, and recompile.
 *
 * The union, not the last card's set: several cards share one `<style>`, and a
 * card re-mounts on every keystroke. Recompiling the union is also what makes
 * the result stable while someone types — a class that disappears mid-edit
 * does not take its CSS with it and flash the layout.
 *
 * @param {string[]} classes
 * @param {{scope: string, styleId: string}} opts `scope` is the selector every
 *   rule is nested under.
 */
export function addClasses(classes, { scope, styleId }) {
  let sheet = sheets.get(styleId);
  if (!sheet) {
    sheet = { scope, names: new Set(), timer: 0 };
    sheets.set(styleId, sheet);
  }
  let fresh = false;
  for (const name of classes) {
    if (!sheet.names.has(name)) {
      sheet.names.add(name);
      fresh = true;
    }
  }
  // Nothing new: the union is what is already on the page, and compiling it
  // again would produce the same bytes. This is the common case — every
  // keystroke re-mounts a card whose classes did not change.
  if (!fresh) return;
  clearTimeout(sheet.timer);
  sheet.timer = setTimeout(() => rebuild(styleId, sheet), 60);
}

async function rebuild(styleId, sheet) {
  const names = [...sheet.names].sort();
  let css = "";
  try {
    const compile = await compiler();
    css = compile(JSON.stringify(names));
  } catch (e) {
    // A card that renders unstyled is a worse-looking page; a card that throws
    // is a broken one. The compiler is a nicety here, so it fails quietly and
    // says why in the console.
    console.warn(`[mb-card] margaui unavailable: ${e.message}`);
    return;
  }
  let el = document.getElementById(styleId);
  if (!el) {
    el = document.createElement("style");
    el.id = styleId;
    document.head.append(el);
  }
  el.textContent = scopeCss(css, sheet.scope);
}

/**
 * Keep `el`'s `data-theme` in step with the reader's colour scheme.
 *
 * margaui picks a theme with `[data-theme="dark"]`, and the scoping below
 * rewrites that onto the SCOPE element rather than the document — so the
 * attribute has to be there, and the page's `<html>` carrying one (or not)
 * says nothing about it. Light is the default in the sheet, so this only ever
 * has to add or remove `dark`.
 *
 * The listener is per element and never removed: an `<mb-card>` that leaves
 * the document takes its own preview with it, and a `MediaQueryList` holding
 * the last reference to a detached node is not a leak worth a lifecycle.
 */
export function followColorScheme(el) {
  const mq = matchMedia("(prefers-color-scheme: dark)");
  const apply = () => {
    el.dataset.theme = mq.matches ? "dark" : "light";
  };
  apply();
  mq.addEventListener("change", apply);
}

/**
 * Nest every rule in `css` under `scope`, and flatten its cascade layers.
 *
 * Parsed by the browser and re-serialized, so the input can be anything CSS
 * is: what the walk does is decide, per rule, whether it is a style rule to be
 * prefixed, a group to recurse into, or a rule that is global by nature and
 * passes through.
 *
 * **Why the layers go.** An UNLAYERED rule beats a layered one whatever their
 * specificities — that is what a layer is for. margaui puts its theme, the
 * preflight and the utilities in `@layer`, which is right when it is the
 * page's stylesheet and exactly wrong here: every host page this lands in has
 * unlayered rules of its own (`button { … }` in the card playground's shell,
 * `input`/`a`/`pre` in the landing site's), and each of them would outrank
 * `.btn`. Flattened, the scope prefix does the work instead — `mb-card
 * .mbc-preview .btn` outranks a bare `button` by specificity, which is a
 * contest margaui can win.
 *
 * Flattening reorders rather than concatenates, because layer ORDER is real
 * cascade information: `@layer theme, base, components, utilities` says a
 * utility beats a component, and the compiled sheet does not emit them in that
 * order. So each layer's rules are collected and re-emitted in the declared
 * order, and the sheet's own unlayered rules go last — which is where the
 * cascade already put them.
 */
export function scopeCss(css, scope) {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(css);
  const order = [];
  const layers = new Map();
  const unlayered = [];
  for (const rule of sheet.cssRules) {
    const text = rule.cssText;
    // `@layer a, b, c;` — the declaration that fixes the order.
    if (text.startsWith("@layer") && !rule.cssRules) {
      for (const name of text.slice(6).replace(";", "").split(",")) {
        const n = name.trim();
        if (n && !order.includes(n)) order.push(n);
      }
      continue;
    }
    // `@layer name { … }` — the rules themselves.
    if (text.startsWith("@layer") && rule.cssRules) {
      const name = (rule.name ?? text.slice(6, text.indexOf("{"))).trim();
      if (!order.includes(name)) order.push(name);
      layers.set(name, (layers.get(name) ?? "") + walk(rule.cssRules, scope));
      continue;
    }
    unlayered.push(walk([rule], scope));
  }
  return (
    order.map((name) => layers.get(name) ?? "").join("") + unlayered.join("")
  );
}

function walk(rules, scope) {
  let out = "";
  for (const rule of rules) {
    // A style rule: prefix its selector list.
    if (rule.selectorText !== undefined && rule.style) {
      const selector = scopeSelector(rule.selectorText, scope);
      // `rule.cssText` re-serializes the whole rule INCLUDING any nested rules
      // (margaui nests `@supports` inside declarations), which is exactly what
      // the body needs to keep; `rule.style.cssText` would drop them. So take
      // the body from the serialized rule rather than from the style map.
      const body = rule.cssText.slice(rule.cssText.indexOf("{"));
      out += selector + " " + body + "\n";
      continue;
    }
    // `@keyframes` names animation steps, not elements — and its children are
    // keyframes, not style rules, so this must not recurse into it.
    if (rule.cssText.startsWith("@keyframes")) {
      out += rule.cssText + "\n";
      continue;
    }
    // A layer nested inside something else (or reached by the single-rule
    // path from scopeCss): inlined, for the reason scopeCss gives.
    if (rule.cssRules && rule.cssText.startsWith("@layer")) {
      out += walk(rule.cssRules, scope);
      continue;
    }
    // A conditional group — `@media`, `@supports`, `@container`. The prelude
    // is whatever precedes the brace; recurse.
    if (rule.cssRules) {
      const head = rule.cssText.slice(0, rule.cssText.indexOf("{"));
      out += head + "{\n" + walk(rule.cssRules, scope) + "}\n";
      continue;
    }
    // `@layer a, b;`, `@property`, `@font-face`: global by definition, and
    // scoping them is either meaningless or a syntax error.
    out += rule.cssText + "\n";
  }
  return out;
}

/**
 * One selector list, rewritten to match inside `scope`.
 *
 * Three cases, and the third is the reason this is not a string concatenation.
 *
 *  - A ROOT-ISH selector (`:root`, `:host`, `html`, `body`) names the document
 *    element, which is exactly what must NOT be reached. It becomes the scope
 *    itself, so the theme's custom properties land on the preview and inherit
 *    down from there — `:root:not(span)` keeps its qualifier and becomes
 *    `.mbc-preview:not(span)`.
 *  - `[data-theme…]` is how margaui selects a theme, and the attribute belongs
 *    on the same element the variables do. It attaches to the scope with no
 *    space: `.mbc-preview[data-theme="dark"]`.
 *  - Anything else is a descendant: `.btn` becomes `.mbc-preview .btn`.
 */
export function scopeSelector(selectorList, scope) {
  // `scope` must be ONE selector. It is prefixed by concatenation — `scope + s`
  // for a themed-root rule, `scope + " " + s` otherwise — so a scope carrying a
  // top-level comma splits the result into two selectors, the first of which is
  // the bare scope element with the rule's body applied to IT. Put alternatives
  // inside `:is(a, b)` instead.
  return splitTopLevel(selectorList)
    .map((sel) => {
      const s = sel.trim();
      // `:where(:root, [data-theme])` — margaui's zero-specificity way of
      // saying "the themed root". Handled by name because taking it apart
      // generically would mean parsing selectors, and this is the one form the
      // stylesheet uses.
      const where = s.match(/^:where\(\s*:root\s*,\s*\[data-theme\]\s*\)/);
      if (where) return scope + s.slice(where[0].length);
      const root = s.match(/^(?::root|:host|html|body)(?![\w-])/);
      if (root) return scope + s.slice(root[0].length);
      if (s.startsWith("[data-theme")) return scope + s;
      return scope + " " + s;
    })
    .join(", ");
}

/**
 * Split a selector list on its top-level commas.
 *
 * `:is(a, b)` and `:where(:root, [data-theme])` both hold commas that are not
 * separators, and splitting on `,` would cut them in half.
 */
function splitTopLevel(list) {
  const out = [];
  let depth = 0;
  let start = 0;
  let quote = "";
  for (let i = 0; i < list.length; i++) {
    const c = list[i];
    if (quote) {
      if (c === quote && list[i - 1] !== "\\") quote = "";
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === "(" || c === "[") depth++;
    else if (c === ")" || c === "]") depth--;
    else if (c === "," && depth === 0) {
      out.push(list.slice(start, i));
      start = i + 1;
    }
  }
  out.push(list.slice(start));
  return out;
}
