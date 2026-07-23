// <mb-playground src="./site/examples/counter.mbt" view="./site/examples/counter.html">
// — an embeddable, editable MoonBit playground for the landing page. Each
// instance shows an editor + a live preview; edits recompile on Ctrl/⌘+Enter
// (or the Run button).
//
// Same three tabs as the standalone playground (../playground/driver.js):
//
//   Component  the .mbt the example is written in
//   View       the .html its views live in (the `view` attribute)
//   Generated  read-only: what `tutuca gen-views` makes of the View tab
//
// The generated module is handed to the compiler as an EXTRA FILE OF THE
// USER'S PACKAGE, which is why the component can name `counter_views()` and
// `CounterMsg` with no import. An element with no `view` attribute keeps the
// single-editor look and compiles its source alone.
//
// All instances share ONE compiler worker (the 5.5 MB in-browser MoonBit
// compiler), reused from the sibling standalone playground payload under
// ./playground/. The worker fetches its interfaces/cores relative to its own
// URL, so pointing at ./playground/compiler.worker.js loads dist/playground/'s
// payload with no duplication. Compiles are cheap once the compiler is loaded;
// each element compiles LAZILY the first time it scrolls into view, so a page
// full of playgrounds doesn't pay for every compile up front.

import { errorDiagnostics, makeCompiler, mount, mountWasm } from "../playground/runtime.js";
import { createEditor } from "../playground/editor.bundle.js";
import {
  componentName,
  componentNames,
  ensureViewgen,
  generateViews,
} from "../playground/viewgen-client.js";

// one shared compiler for the whole page; init() is memoized inside makeCompiler
const compiler = makeCompiler("./playground/compiler.worker.js");

// Which backends the assembled payload actually carries (wasm-gc is only real
// when the site was built without JS_ONLY). Fetched once from the manifest and
// shared by every element so the toggle can't offer a target the worker can't
// load. Falls back to js-only if the manifest can't be read.
let _availableTargets;
function availableTargets() {
  return (_availableTargets ??= fetch("./playground/manifest.json")
    .then((r) => r.json())
    .then((m) => Object.keys(m.targets || { js: 1 }))
    .catch(() => ["js"]));
}

const STYLE = `
  :host { display: block; margin: 1rem 0; color-scheme: light dark; }
  .wrap {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.75rem;
    border: 1px solid var(--border-color, #898ea4);
    border-radius: var(--standard-border-radius, 6px);
    overflow: hidden;
    background: var(--accent-bg, #f5f7ff);
    /* Keep the whole playground on screen: cap it at 80vh. The editor and
       preview scroll internally rather than growing the page. */
    max-height: 80vh;
  }
  /* Cap the editor so a long example scrolls in place instead of stretching
     the row (CodeMirror auto-grows to its content otherwise). */
  .editor { display: flex; flex-direction: column; min-height: 20rem; max-height: 80vh; min-width: 0; }
  .toolbar {
    display: flex; align-items: center; gap: 0.5rem;
    padding: 0.35rem 0.5rem;
    border-bottom: 1px solid var(--border-color, #898ea4);
  }
  .toolbar button {
    font: inherit; font-size: 0.8rem; cursor: pointer;
    padding: 0.2rem 0.7rem; border-radius: 4px;
    border: 1px solid var(--border-color, #898ea4); background: transparent; color: inherit;
  }
  .toolbar select {
    font: inherit; font-size: 0.75rem; cursor: pointer;
    padding: 0.15rem 0.3rem; border-radius: 4px;
    border: 1px solid var(--border-color, #898ea4); background: transparent; color: inherit;
  }
  /* Hidden on js-only builds (no wasm-gc payload to switch to). */
  .toolbar select[hidden] { display: none; }
  .status { font-size: 0.75rem; opacity: 0.8; }
  .status.busy { color: #b58900; }
  .status.ok { color: #2a7; }
  .status.error { color: #c33; }
  /* Tabs over the editor: the component, the view HTML it is generated from,
     and the read-only generated module. Hidden when there is no view. */
  .tabs { display: flex; flex: 0 0 auto; border-bottom: 1px solid var(--border-color, #898ea4); }
  .tabs[hidden] { display: none; }
  .tabs button {
    appearance: none; background: none; color: inherit;
    border: 0; border-bottom: 2px solid transparent;
    padding: 0.3rem 0.7rem; font: inherit; font-size: 0.75rem; cursor: pointer; opacity: 0.65;
  }
  .tabs button[aria-selected="true"] { opacity: 1; border-bottom-color: currentColor; font-weight: 600; }
  .tabs .spacer { flex: 1; }
  .tabs .note { align-self: center; font-size: 0.68rem; opacity: 0.55; padding-right: 0.6rem; }
  /* One absolutely-positioned pane per tab, so switching keeps the height. */
  .editors { flex: 1; min-height: 0; position: relative; }
  .editors > div { position: absolute; inset: 0; overflow: hidden; }
  .editors > div[hidden] { display: none; }
  .editors .cm-editor { height: 100%; }
  .diagnostics {
    margin: 0; max-height: 8rem; overflow: auto;
    padding: 0 0.6rem; white-space: pre-wrap;
    font-family: ui-monospace, monospace; font-size: 11px; color: #c33;
  }
  .diagnostics:empty { display: none; }
  .preview { min-width: 0; border-left: 1px solid var(--border-color, #898ea4); background: var(--bg, #fff); }
  .preview iframe { width: 100%; height: 100%; min-height: 20rem; border: 0; }
  @media (max-width: 768px) {
    /* Stacked layout: editor above preview. Drop the 80vh cap so the preview
       isn't clipped — each pane keeps its own min-height instead. */
    .wrap { grid-template-columns: 1fr; max-height: none; }
    .editor { max-height: none; }
    .preview { border-left: 0; border-top: 1px solid var(--border-color, #898ea4); }
  }
`;

const TABS = ["component", "view", "generated"];

class MbPlayground extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._compiling = false;
    // The view SOURCE, not the view editor, is the source of truth: the View
    // and Generated editors are built lazily (a page of embeds would otherwise
    // pay for three CodeMirrors each), so generation must not depend on them.
    this._viewSrc = "";
    this._generated = { module: "", ir: "" };
    this._genTimer = null;
  }

  async connectedCallback() {
    this.shadowRoot.innerHTML = `
      <style>${STYLE}</style>
      <div class="wrap">
        <div class="editor">
          <div class="toolbar">
            <button class="run" type="button">Run ▶</button>
            <select class="target" title="Compile target" hidden>
              <option value="js">js</option>
              <option value="wasm-gc">wasm-gc</option>
            </select>
            <span class="status"></span>
            <span style="font-size:0.7rem;opacity:0.5;margin-left:auto">Ctrl/⌘+Enter</span>
          </div>
          <div class="tabs" role="tablist" hidden>
            <button type="button" role="tab" data-tab="component" aria-selected="true">Component</button>
            <button type="button" role="tab" data-tab="view" aria-selected="false">View</button>
            <button type="button" role="tab" data-tab="generated" aria-selected="false">Generated</button>
            <span class="spacer"></span>
            <span class="note"></span>
          </div>
          <div class="editors">
            <div class="pane" data-pane="component" role="tabpanel"></div>
            <div class="pane" data-pane="view" role="tabpanel" hidden></div>
            <div class="pane" data-pane="generated" role="tabpanel" hidden></div>
          </div>
          <pre class="diagnostics"></pre>
        </div>
        <div class="preview"></div>
      </div>`;

    this.statusEl = this.shadowRoot.querySelector(".status");
    this.diagsEl = this.shadowRoot.querySelector(".diagnostics");
    this.previewEl = this.shadowRoot.querySelector(".preview");
    this.targetEl = this.shadowRoot.querySelector(".target");
    this.tabsEl = this.shadowRoot.querySelector(".tabs");
    this.noteEl = this.shadowRoot.querySelector(".note");

    // Reveal the target toggle only for backends the payload actually carries;
    // re-compile the current editor content whenever the target changes.
    availableTargets().then((targets) => {
      for (const opt of this.targetEl.options) opt.disabled = !targets.includes(opt.value);
      // Show the toggle only when there's more than one runnable target.
      this.targetEl.hidden = targets.length < 2;
    });
    this.targetEl.addEventListener("change", () => this.run());

    // CodeMirror lives in the shadow root; pass `root` so it resolves its DOM.
    this.editors = {
      component: createEditor({
        parent: this.pane("component"),
        root: this.shadowRoot,
        onRun: () => this.run(),
      }),
    };

    for (const b of this.tabsEl.querySelectorAll("button")) {
      b.addEventListener("click", () => this.selectTab(b.dataset.tab));
    }
    this.shadowRoot.querySelector(".run").addEventListener("click", () => this.run());

    await this.loadSource();

    // compile + run the first time this element scrolls into view
    this._io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            this._io.disconnect();
            this.run();
          }
        }
      },
      { rootMargin: "200px" },
    );
    this._io.observe(this);
  }

  disconnectedCallback() {
    this._io?.disconnect();
    clearTimeout(this._genTimer);
    for (const ed of Object.values(this.editors || {})) ed.destroy();
  }

  pane(name) {
    return this.shadowRoot.querySelector(`[data-pane="${name}"]`);
  }

  // --- tabs ----------------------------------------------------------------
  // The View and Generated editors are created the first time their tab is
  // revealed; CodeMirror also measures lazily, so nudge a freshly shown pane.
  selectTab(name) {
    for (const t of TABS) {
      const on = t === name;
      this.tabsEl.querySelector(`[data-tab="${t}"]`).setAttribute("aria-selected", String(on));
      this.pane(t).hidden = !on;
    }
    this.editorFor(name).view.requestMeasure();
  }

  editorFor(name) {
    if (this.editors[name]) return this.editors[name];
    if (name === "view") {
      this.editors.view = createEditor({
        parent: this.pane("view"),
        root: this.shadowRoot,
        doc: this._viewSrc,
        lang: "html",
        onRun: () => this.run(),
        onChange: (text) => {
          this._viewSrc = text;
          this.scheduleGenerate();
        },
      });
    } else {
      this.editors.generated = createEditor({
        parent: this.pane("generated"),
        root: this.shadowRoot,
        doc: this.generatedText(),
        readOnly: true,
      });
    }
    return this.editors[name];
  }

  // Source comes from the `src` attribute (fetched .mbt) or inline text
  // content; the view from the `view` attribute (a fetched .html).
  async loadSource() {
    const src = this.getAttribute("src");
    const viewSrc = this.getAttribute("view");
    const [code, view] = await Promise.all([
      src ? this.fetchText(src) : Promise.resolve(this.textContent.trim()),
      viewSrc ? this.fetchText(viewSrc) : Promise.resolve(null),
    ]);
    this.editors.component.setValue(code);
    if (view != null) {
      this._viewSrc = view;
      this.tabsEl.hidden = false;
    }
  }

  async fetchText(url) {
    try {
      const resp = await fetch(url);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return await resp.text();
    } catch (e) {
      return `// failed to load ${url}: ${e.message}`;
    }
  }

  setStatus(msg, cls) {
    this.statusEl.textContent = msg;
    this.statusEl.className = "status " + (cls || "");
  }

  // --- view -> generated module --------------------------------------------
  generatedText() {
    const { module: mod, ir } = this._generated;
    return ir ? mod + "\n" + ir : mod;
  }

  // Regenerate from the view source. Returns true when the module is usable; a
  // generation failure is reported like a compile error and leaves the previous
  // module in place so a half-typed tag does not blank the Generated tab.
  generate() {
    const html = this._viewSrc.trim();
    if (!html) {
      this._generated = { module: "", ir: "" };
      return true;
    }
    const name = componentName(html);
    const r = generateViews(html, name);
    if (!r.ok) {
      this.noteEl.textContent = "view error";
      this.diagsEl.textContent = `view.html: ${r.error}`;
      return false;
    }
    this._generated = { module: r.module, ir: r.ir };
    this.editors.generated?.setValue(this.generatedText());
    const declared = componentNames(html).join(", ");
    this.noteEl.textContent = r.ir
      ? `${declared} — types + compiled tree`
      : `${declared} — types only (a macro blocks the compiled tree)`;
    return true;
  }

  // Debounced so typing a tag does not regenerate on every keystroke.
  scheduleGenerate() {
    clearTimeout(this._genTimer);
    this._genTimer = setTimeout(() => {
      if (this.generate()) this.diagsEl.textContent = "";
    }, 250);
  }

  async run() {
    if (this._compiling) return;
    this._compiling = true;
    const target = this.targetEl.value;
    this.setStatus(`compiling (${target})…`, "busy");
    this.diagsEl.textContent = "";
    try {
      // The generator is a separate 1.3 MB payload; load it only for the
      // elements that have a View tab, and only when one actually runs.
      if (this._viewSrc) await ensureViewgen();
      await compiler.init(target); // switch the worker's payload if the target changed
      // Always regenerate before compiling: the View tab is the source of
      // truth for the generated module, and a debounce may still be pending.
      if (!this.generate()) {
        this.setStatus("view error", "error");
        return;
      }
      const r = await compiler.compile(
        this.editors.component.getValue(),
        this._generated.module,
        this._generated.ir,
      );
      const errs = errorDiagnostics(r.diagnostics);
      this.diagsEl.textContent = (r.diagnostics || []).join("\n\n");
      this.editors.component.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
      if (!r.ok || errs.length) {
        // A build can fail with nothing errorDiagnostics() recognizes — a
        // non-exhaustive match arrives as "Error Warning (partial_match)",
        // which is exactly what a regenerated view produces when the component
        // has not caught up. Don't report that as "0 errors".
        this.setStatus(errs.length ? `compile errors (${errs.length})` : "compile failed", "error");
        return;
      }
      if (target === "wasm-gc") {
        // linkCore returned a wasm binary; instantiate + drive the DOM from wasm.
        // A string-ABI mismatch in the vendored in-browser linker currently makes
        // this throw a WebAssembly.CompileError — surfaced in the diagnostics pane.
        await mountWasm(this.previewEl, r.result, {});
      } else {
        mount(this.previewEl, new TextDecoder().decode(r.result), {});
      }
      this.setStatus(`ok — ${target} — ${r.ms} ms`, "ok");
    } catch (e) {
      this.setStatus(target === "wasm-gc" ? "wasm instantiate failed" : "error", "error");
      this.diagsEl.textContent = String(e.stack || e.message || e);
      this.editors.component.setDiagnostics([]);
    } finally {
      this._compiling = false;
    }
  }
}

customElements.define("mb-playground", MbPlayground);
