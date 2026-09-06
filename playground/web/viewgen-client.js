// The view generator, as a page uses it: html -> the MoonBit modules
// `tutuca gen` would write next to the component.
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
// …). A `.tutu` names its components itself, in the headings under `spec:`
// and `view:`, so there is nothing to fill in and no third input to keep in
// sync. `View` is the fallback for a file that declares none.
export function componentName(src) {
  const names = componentNames(src);
  return names.length ? names[0] : "View";
}

// A heading under `spec:` or `view:` names a component; `Note.edit:` is one of
// its views and `macro row(…):` is a macro shared by the file. Read from both
// sections, because a file may declare state for a component whose views are
// built in MoonBit, and views for one whose state is.
const SECTION_RE = /^(spec|view):[ \t]*$/;
const HEADING_RE = /^  ([A-Z][\w]*)(?:\.\w+)?:/;

export function componentNames(src) {
  const names = [];
  let inside = false;
  for (const line of src.split("\n")) {
    if (/^[a-z]+:[ \t]*$/.test(line)) {
      inside = SECTION_RE.test(line);
      continue;
    }
    if (!inside) continue;
    const m = HEADING_RE.exec(line);
    if (m && !names.includes(m[1])) names.push(m[1]);
  }
  return names;
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
