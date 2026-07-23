// The view generator, as a page uses it: html -> the MoonBit modules
// `tutuca gen-views` would write next to the component.
//
// The generator itself is viewgen/ compiled to JS (viewgen.js, ~1.3 MB,
// publishing one global entry point `__tutucaViewgen(html, name) -> JSON`).
// It is loaded ON DEMAND here, because the landing site embeds many
// playgrounds and must not pay for the generator until one of them actually
// runs. The standalone playground page still loads it up front with a plain
// <script> tag; ensureViewgen() then resolves immediately.
//
// Shared by the standalone driver (./driver.js) and the embeddable
// <mb-playground> element (../site/embed.js) so the two cannot drift.

// The component name heads the generated types (CounterMsg, counter_views,
// …). It is read from the view file's first `<!-- name: X -->` comment so the
// component and view tabs stay in sync without a third input to fill in. A
// view file that names its templates (`<template id="Counter">`) ignores it.
const NAME_RE = /<!--\s*name:\s*([A-Za-z][\w]*)\s*-->/;

export function componentName(html) {
  const m = NAME_RE.exec(html);
  return m ? m[1] : "View";
}

// A template id says which component a view belongs to (`Counter`,
// `Counter:row`); `macro:` ids declare a macro shared by the file. A file that
// names its templates carries a whole module's components, and the fallback
// name above is never consulted — so report what it actually declares.
const TEMPLATE_ID_RE = /<template[^>]*\bid\s*=\s*["']([^"']+)["']/gi;

export function componentNames(html) {
  const names = [];
  // comments first: a view file may TALK about `<template id="…">`
  for (const [, id] of html.replace(/<!--[\s\S]*?-->/g, "").matchAll(TEMPLATE_ID_RE)) {
    if (id.startsWith("macro:")) continue;
    const name = id.split(":")[0];
    if (name && !names.includes(name)) names.push(name);
  }
  return names.length ? names : [componentName(html)];
}

// Memoized: many callers (a page full of embedded playgrounds) share one load.
let loading = null;

// Resolve once `globalThis.__tutucaViewgen` is callable. Rejects if the
// generator script fails to load; the memo is dropped so a later call retries.
export function ensureViewgen(url = new URL("./viewgen.js", import.meta.url)) {
  if (typeof globalThis.__tutucaViewgen === "function") {
    return Promise.resolve(globalThis.__tutucaViewgen);
  }
  loading ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = String(url);
    script.onload = () =>
      typeof globalThis.__tutucaViewgen === "function"
        ? resolve(globalThis.__tutucaViewgen)
        : reject(new Error("viewgen.js loaded but published no generator"));
    script.onerror = () => reject(new Error(`failed to load ${url}`));
    document.head.appendChild(script);
  }).catch((e) => {
    loading = null;
    throw e;
  });
  return loading;
}

// Generate the modules for one view file. Never throws: a bad view (or a
// generator crash) comes back as `{ ok: false, error }` so the caller can
// report it like a compile error.
//
// `ir` is empty when the views use a macro — macros are registered from
// MoonBit at runtime, so they cannot be expanded ahead of time and there is
// no compiled tree to emit.
export function generateViews(html, name = componentName(html)) {
  const gen = globalThis.__tutucaViewgen;
  if (typeof gen !== "function") {
    return { ok: false, error: "generator not loaded" };
  }
  let r;
  try {
    r = JSON.parse(gen(html, name));
  } catch (e) {
    return { ok: false, error: String(e.message || e) };
  }
  return r.ok
    ? { ok: true, module: r.module, ir: r.ir || "" }
    : { ok: false, error: r.error };
}
