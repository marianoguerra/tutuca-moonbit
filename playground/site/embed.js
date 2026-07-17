// <mb-playground src="./site/examples/counter.mbt"> — an embeddable, editable
// MoonBit playground for the landing page. Each instance shows an editor + a
// live preview; edits recompile on Ctrl/⌘+Enter (or the Run button).
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
  .cm-host { flex: 1; min-height: 0; overflow: hidden; }
  .cm-host .cm-editor { height: 100%; }
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

class MbPlayground extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._compiling = false;
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
          <div class="cm-host"></div>
          <pre class="diagnostics"></pre>
        </div>
        <div class="preview"></div>
      </div>`;

    this.statusEl = this.shadowRoot.querySelector(".status");
    this.diagsEl = this.shadowRoot.querySelector(".diagnostics");
    this.previewEl = this.shadowRoot.querySelector(".preview");
    this.targetEl = this.shadowRoot.querySelector(".target");

    // Reveal the target toggle only for backends the payload actually carries;
    // re-compile the current editor content whenever the target changes.
    availableTargets().then((targets) => {
      for (const opt of this.targetEl.options) opt.disabled = !targets.includes(opt.value);
      // Show the toggle only when there's more than one runnable target.
      this.targetEl.hidden = targets.length < 2;
    });
    this.targetEl.addEventListener("change", () => this.run());

    // CodeMirror lives in the shadow root; pass `root` so it resolves its DOM.
    this.editor = createEditor({
      parent: this.shadowRoot.querySelector(".cm-host"),
      root: this.shadowRoot,
      onRun: () => this.run(),
    });

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
    this.editor?.destroy();
  }

  // Source comes from the `src` attribute (fetched .mbt) or inline text content.
  async loadSource() {
    const src = this.getAttribute("src");
    if (!src) {
      this.editor.setValue(this.textContent.trim());
      return;
    }
    try {
      const resp = await fetch(src);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      this.editor.setValue(await resp.text());
    } catch (e) {
      this.editor.setValue(`// failed to load ${src}: ${e.message}`);
    }
  }

  setStatus(msg, cls) {
    this.statusEl.textContent = msg;
    this.statusEl.className = "status " + (cls || "");
  }

  async run() {
    if (this._compiling) return;
    this._compiling = true;
    const target = this.targetEl.value;
    this.setStatus(`compiling (${target})…`, "busy");
    this.diagsEl.textContent = "";
    try {
      await compiler.init(target); // switch the worker's payload if the target changed
      const r = await compiler.compile(this.editor.getValue());
      const errs = errorDiagnostics(r.diagnostics);
      this.diagsEl.textContent = (r.diagnostics || []).join("\n\n");
      this.editor.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
      if (!r.ok || errs.length) {
        this.setStatus(`compile errors (${errs.length})`, "error");
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
      this.editor.setDiagnostics([]);
    } finally {
      this._compiling = false;
    }
  }
}

customElements.define("mb-playground", MbPlayground);
