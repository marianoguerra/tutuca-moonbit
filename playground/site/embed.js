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

import { errorDiagnostics, makeCompiler, mount } from "../playground/runtime.js";
import { createEditor } from "../playground/editor.bundle.js";

// one shared compiler for the whole page; init() is memoized inside makeCompiler
const compiler = makeCompiler("./playground/compiler.worker.js");

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
  }
  .editor { display: flex; flex-direction: column; min-height: 20rem; min-width: 0; }
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
    .wrap { grid-template-columns: 1fr; }
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
    this.setStatus("compiling…", "busy");
    this.diagsEl.textContent = "";
    try {
      await compiler.init("js");
      const r = await compiler.compile(this.editor.getValue());
      const errs = errorDiagnostics(r.diagnostics);
      this.diagsEl.textContent = (r.diagnostics || []).join("\n\n");
      this.editor.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
      if (!r.ok || errs.length) {
        this.setStatus(`compile errors (${errs.length})`, "error");
        return;
      }
      const js = new TextDecoder().decode(r.result);
      mount(this.previewEl, js, {});
      this.setStatus(`ok — ${r.ms} ms`, "ok");
    } catch (e) {
      this.setStatus("error", "error");
      this.diagsEl.textContent = String(e.message || e);
      this.editor.setDiagnostics([]);
    } finally {
      this._compiling = false;
    }
  }
}

customElements.define("mb-playground", MbPlayground);
