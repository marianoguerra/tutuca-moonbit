// <mb-card src="./cards/counter.html"> — an embeddable, editable CARD.
//
// The card sibling of `<mb-playground>` (playground/site/embed.js), and the
// difference between the two is the whole reason this file is short. That one
// carries an in-browser MoonBit compiler: a 5.5 MB worker, a per-target
// prebuilt closure, a manifest, a target toggle, a fallback path for engines
// without JS-String-Builtins, and an iframe to mount the result in. This one
// has a `.html` file and a runtime that is already on the page. The edit loop
// is one call:
//
//   globalThis.__tutucard.mount(previewId, source, name)
//
// and everything else here draws what it answers.
//
// Two deliberate simplifications against the standalone card playground
// (tutucard/web/shell.js), which is a tool where this is an illustration: no
// structured editor (the raw file IS the point being made), and no state or
// activity panels (a reader wants to see the thing work, and the panels are
// what you open when you are debugging one).
//
// Two things it CAN be asked for, per element, because each is a download and
// most cards need neither: `margaui` compiles the card's class names into CSS
// (see styleClasses), and `codemirror` swaps the textarea for the editor the
// other playgrounds use (see upgradeEditor). Both are upgrades of something
// that already works, so a page that ships the element without the files gets
// a plain, working card and a line in the console.
//
// LIGHT DOM, not a shadow root, and that is load-bearing rather than lazy. A
// card's `<style>` blocks are installed into the document by the framework and
// scoped there, so a shadow root would cut every card off from its own styles;
// and the host mounts by element id, which `document.getElementById` has to be
// able to find. The visible cost is that the page's CSS reaches the preview —
// which for an example embedded in a page is the behaviour you want.

import { componentOf } from "./regions.js";
import { addClasses, followColorScheme } from "./margaui.js";

/** Debounce, so a fast typist re-mounts on pauses rather than per keystroke. */
const DEBOUNCE_MS = 180;

/** One id per element, so several cards on a page cannot collide. */
let seq = 0;

/**
 * The stylesheet, added once for the whole page.
 *
 * A `<style>` rather than the constructable kind: this is one small rule set
 * on a documentation page, and adoptedStyleSheets would buy nothing but a
 * feature check. Every selector is under `mb-card` so a page that never uses
 * one pays nothing, and so nothing here reaches a card's own markup.
 *
 * The element's own box is styled through `:where`, which zeroes the rule's
 * specificity: this sheet is appended when the first card connects, so it
 * lands AFTER the page's stylesheet and would otherwise win every tie by
 * order alone. It won the landing page's `margin: 1.5rem auto` that way, and
 * the card sat flush left beside the playgrounds it is meant to be compared
 * with. What is here is a DEFAULT for a page that says nothing; the page has
 * the last word on where its own element sits. `<mb-playground>` gets this
 * free from `:host`, which page rules already outrank.
 */
const STYLE = `
/* NO BACKTICKS BELOW THIS LINE — this is a template literal, and a backtick in
   a CSS comment ends it mid-file. It has happened three times. */
:where(mb-card) {
  display: block;
  /* Border inside the width a page gives it, so a card capped at the same
     max-width as an mb-playground lines up with it edge for edge. */
  box-sizing: border-box;
  margin: 1rem 0;
  border: 1px solid var(--border-color, #898ea4);
  border-radius: var(--standard-border-radius, 5px);
  overflow: hidden;
  background: var(--accent-bg, #f5f7ff);
}
mb-card .mbc-bar {
  display: flex; align-items: center; gap: 0.5rem;
  padding: 0.35rem 0.6rem;
  border-bottom: 1px solid var(--border-color, #898ea4);
  font-size: 0.75rem;
}
mb-card .mbc-bar .mbc-name { font-weight: 600; }
mb-card .mbc-bar .mbc-note { margin-left: auto; opacity: 0.55; font-size: 0.7rem; }
mb-card .mbc-bar .mbc-reset {
  font: inherit; cursor: pointer; padding: 0 0.4rem;
  border: 1px solid var(--border-color, #898ea4); border-radius: 3px;
  background: transparent; color: inherit;
}
/* Hidden rather than disabled while the card is untouched: a control that has
   never had anything to undo is noise on a page of eight examples. */
mb-card .mbc-bar .mbc-reset[hidden] { display: none; }
mb-card .mbc-status.good { color: #2a7; }
mb-card .mbc-status.warn { color: #b58900; }
mb-card .mbc-status.bad { color: #c33; }
/* The source gets the larger share: it is the thing being read, its lines are
   as long as its author wrote them, and a preview is usually a few controls. */
mb-card .mbc-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr);
}
/* The height comes from the rows attribute this element sets per card (see
   fitRows below). The bounds are the two cases that would otherwise read
   badly: a six-line card given a fixed 18rem box of empty space, and a
   two-hundred-line one given a page of scrollbar. */
mb-card .mbc-source {
  display: block; width: 100%; box-sizing: border-box;
  min-height: 6rem; max-height: 32rem; resize: vertical;
  border: 0; padding: 0.6rem;
  background: transparent; color: inherit;
  font-family: ui-monospace, monospace; font-size: 0.75rem; line-height: 1.5;
  tab-size: 2;
}
mb-card .mbc-source:focus { outline: none; }
/* display:block above outranks the UA's [hidden] { display: none }, so the
   textarea CodeMirror replaced would otherwise stay on the page above it,
   holding a stale copy of the card. */
mb-card .mbc-source[hidden] { display: none; }
/* The editor pane. It holds the textarea by default and a CodeMirror after an
   mb-card with the codemirror attribute upgrades it. The bounds are the same
   either way, so a card does not change size when the bundle lands. */
mb-card .mbc-edit { min-width: 0; }
mb-card .mbc-cm .cm-editor { height: auto; max-height: 32rem; }
mb-card .mbc-cm .cm-scroller { overflow: auto; }
mb-card .mbc-right {
  border-left: 1px solid var(--border-color, #898ea4);
  background: var(--bg, #fff);
  display: flex; flex-direction: column; min-width: 0;
}
mb-card .mbc-preview { padding: 0.75rem; flex: 1; overflow: auto; }
/* A card that cannot load keeps its last render rather than blanking: a
   syntax error is the ordinary state of a half-typed line, and a preview that
   empties between two keystrokes is worse than one that is visibly behind. */
mb-card .mbc-preview.stale { opacity: 0.45; }
mb-card .mbc-issues {
  margin: 0; padding: 0; list-style: none;
  max-height: 9rem; overflow: auto;
  border-top: 1px solid var(--border-color, #898ea4);
  font-family: ui-monospace, monospace; font-size: 0.7rem;
}
mb-card .mbc-issues:empty { display: none; }
mb-card .mbc-issues li { display: flex; gap: 0.4rem; padding: 0.25rem 0.6rem; }
mb-card .mbc-issues .mbc-where {
  font: inherit; cursor: pointer; padding: 0 0.3rem;
  border: 1px solid var(--border-color, #898ea4); border-radius: 3px;
  background: transparent; color: inherit; flex: 0 0 auto;
}
mb-card .mbc-issues code { color: var(--accent, #0d47a1); flex: 0 0 auto; }
@media (max-width: 768px) {
  mb-card .mbc-grid { grid-template-columns: 1fr; }
  mb-card .mbc-right { border-left: 0; border-top: 1px solid var(--border-color, #898ea4); }
}
`;

function installStyle() {
  if (document.getElementById("mb-card-style")) return;
  const el = document.createElement("style");
  el.id = "mb-card-style";
  el.textContent = STYLE;
  document.head.append(el);
}

class MbCard extends HTMLElement {
  connectedCallback() {
    // Guard against a re-connect (a move in the DOM re-runs this): the element
    // keeps its id and its app, and rebuilding both would leave the old one
    // mounted with nothing pointing at it.
    if (this.previewId) return;
    installStyle();
    this.previewId = `mb-card-preview-${++seq}`;
    this.innerHTML = `
      <div class="mbc-bar">
        <span class="mbc-name"></span>
        <span class="mbc-status">…</span>
        <button class="mbc-reset" type="button" hidden>reset</button>
        <span class="mbc-note">edit the card — it re-mounts as you type</span>
      </div>
      <div class="mbc-grid">
        <div class="mbc-edit">
          <textarea class="mbc-source" spellcheck="false" autocomplete="off"
            autocapitalize="off" autocorrect="off" aria-label="card source"></textarea>
        </div>
        <div class="mbc-right">
          <div class="mbc-preview" id="${this.previewId}"></div>
          <ul class="mbc-issues"></ul>
        </div>
      </div>`;
    this.editEl = this.querySelector(".mbc-edit");
    this.sourceEl = this.querySelector(".mbc-source");
    this.previewEl = this.querySelector(".mbc-preview");
    this.issuesEl = this.querySelector(".mbc-issues");
    this.statusEl = this.querySelector(".mbc-status");
    this.nameEl = this.querySelector(".mbc-name");
    this.resetEl = this.querySelector(".mbc-reset");
    this.sourceEl.addEventListener("input", () => this.scheduleReload());
    this.resetEl.addEventListener("click", () => this.reset());

    this.loadSource().then(() => {
      // The editor is an upgrade of what is already there, so a failed import
      // leaves a working card rather than an empty box.
      this.upgradeEditor();
      // Mount the first time this element scrolls into view. A card is cheap
      // — no compiler, nothing fetched — but a page of them still does nothing
      // until it is looked at, and a reader who never scrolls down pays for
      // nothing they did not see.
      this._io = new IntersectionObserver(
        (entries) => {
          for (const e of entries) {
            if (!e.isIntersecting) continue;
            this._io.disconnect();
            this.reload();
          }
        },
        { rootMargin: "200px" },
      );
      this._io.observe(this);
    });
  }

  disconnectedCallback() {
    this._io?.disconnect();
    clearTimeout(this._timer);
    // CodeMirror holds a matchMedia listener for the light/dark swap, which
    // outlives the DOM node otherwise.
    this.cm?.destroy();
    this.cm = null;
    // The app holds transactor subscriptions and delegated DOM listeners, and
    // nothing else will ever call for them again: this element is the only
    // thing that knows its mount point.
    globalThis.__tutucard?.unmount(this.previewId);
    this.previewId = null;
  }

  /** The card, from the `src` attribute. */
  async loadSource() {
    const src = this.getAttribute("src");
    if (!src) {
      this.setSource("<!-- <mb-card> needs a src -->");
      return;
    }
    try {
      const resp = await fetch(src);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      this.setSource(await resp.text());
    } catch (e) {
      this.setSource(`<!-- failed to load ${src}: ${e.message} -->`);
    }
  }

  /**
   * Put a card in the editor and remember it as the one to go back to.
   *
   * The fetched text is the ONLY thing `reset` restores: an embedded example
   * is an invitation to break it, and the way back has to be the file the page
   * meant to show rather than whatever the last successful parse happened to
   * be.
   */
  setSource(text) {
    this.original = text;
    this.setText(text);
    this.fitRows();
    this.syncReset();
  }

  /** Put the fetched card back, and mount it. */
  reset() {
    if (this.original == null) return;
    clearTimeout(this._timer);
    this.setText(this.original);
    this.fitRows();
    this.syncReset();
    this.reload();
  }

  /**
   * The card being edited, and the one place that knows where it lives.
   *
   * Everything below reads and writes the source through these three, so the
   * CodeMirror upgrade is a swap of one field rather than a second copy of the
   * element's logic.
   */
  text() {
    return this.cm ? this.cm.getValue() : this.sourceEl.value;
  }

  setText(value) {
    if (this.cm) this.cm.setValue(value);
    else this.sourceEl.value = value;
  }

  /** Select the characters an issue is about, and show them. */
  selectRange(from, to) {
    if (this.cm) {
      this.cm.view.dispatch({
        selection: { anchor: from, head: to },
        scrollIntoView: true,
      });
      this.cm.focus();
      return;
    }
    this.sourceEl.focus();
    this.sourceEl.setSelectionRange(from, to);
  }

  syncReset() {
    this.resetEl.hidden = this.text() === this.original;
  }

  /**
   * Size the editor to the card it holds.
   *
   * A page of examples is a page of DIFFERENT LENGTHS — the shortest card here
   * is a schema and a template, the longest is four handlers and a stylesheet
   * — and one fixed height serves neither. The bounds keep a one-line card
   * from being a slit and a long one from being the whole scroll.
   */
  fitRows() {
    // CodeMirror grows with its document and stops at the CSS max-height, so
    // this is the textarea's problem only.
    if (this.cm) return;
    const lines = this.sourceEl.value.split("\n").length;
    this.sourceEl.rows = Math.max(8, Math.min(lines + 1, 24));
  }

  scheduleReload() {
    // Immediately, not on the debounce: the button offers a way back from the
    // edit that is being typed, and appearing a fifth of a second late reads
    // as the page lagging.
    this.syncReset();
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.reload(), DEBOUNCE_MS);
  }

  setStatus(text, cls) {
    this.statusEl.textContent = text;
    this.statusEl.className = "mbc-status " + (cls || "");
  }

  /** Parse, check, mount, and draw what came back. */
  reload() {
    if (!globalThis.__tutucard) {
      this.setStatus("runtime did not load", "bad");
      return;
    }
    const source = this.text();
    const report = JSON.parse(
      globalThis.__tutucard.mount(
        this.previewId,
        source,
        componentOf(source) || "Card",
      ),
    );
    if (!report.ok) {
      this.previewEl.classList.add("stale");
      this.setStatus("cannot load", "bad");
      this.drawIssues([
        {
          line: report.line,
          code: "SYNTAX",
          // The loader's message names its own line because it is also what a
          // CLI would print. The line button says that here, so drop it.
          message: report.error.replace(/^line \d+: /, ""),
          start: report.start,
          end: report.end,
        },
      ]);
      return;
    }
    this.previewEl.classList.remove("stale");
    this.styleClasses();
    this.nameEl.textContent = report.component;
    const n = report.issues.length;
    this.setStatus(
      n === 0 ? "ok" : `${n} issue${n === 1 ? "" : "s"}`,
      n === 0 ? "good" : "warn",
    );
    this.drawIssues(report.issues);
  }

  /**
   * Swap the textarea for CodeMirror, for `<mb-card codemirror>`.
   *
   * OPT-IN, and for the same reason margaui is: the bundle is ~330 KB, which
   * is more than the rest of this element and its runtime's front end put
   * together. A textarea is a perfectly good place to change three characters
   * and watch what happens, which is what most embedded examples are for;
   * highlighting earns its weight on a page someone is meant to READ code on.
   *
   * An upgrade rather than a construction: the textarea already holds the
   * card, so an import that fails (a page that shipped the element without the
   * bundle) leaves a working editor and a line in the console. It is the same
   * editor the two playgrounds use — one seam, one MoonBit mode, one view mode
   * — reached through `./editor.bundle.js`, which sits beside this file.
   */
  async upgradeEditor() {
    if (!this.hasAttribute("codemirror") || this.cm) return;
    let createEditor;
    try {
      ({ createEditor } = await import("./editor.bundle.js"));
    } catch (e) {
      console.warn(`[mb-card] CodeMirror unavailable: ${e.message}`);
      return;
    }
    // The element may have left the document while the bundle was in flight.
    if (!this.previewId) return;
    this.cm = createEditor({
      parent: this.editEl,
      doc: this.sourceEl.value,
      lang: "html",
      onChange: () => this.scheduleReload(),
    });
    this.sourceEl.hidden = true;
    this.editEl.classList.add("mbc-cm");
  }

  /**
   * Compile this card's class names with margaui, for `<mb-card margaui>`.
   *
   * OPT-IN, because the compiler is ~0.5 MB of wasm and most cards do not need
   * it: a card can carry its own `<style>`, which the framework scopes to the
   * view and which costs a page nothing. An element that asks for margaui gets
   * it for the whole page — one sheet, the union of every asking card's
   * classes, scoped so it cannot reach the prose around them.
   */
  styleClasses() {
    if (!this.hasAttribute("margaui")) return;
    const classesAt = globalThis.__tutucard?.classesAt;
    if (!classesAt) return;
    let classes = [];
    try {
      classes = JSON.parse(classesAt(this.previewId));
    } catch {
      return;
    }
    if (!classes.length) return;
    // The theme attribute belongs on the scope element, which is this preview:
    // see followColorScheme. Set once, on the first mount that asks for CSS.
    if (!this.previewEl.dataset.theme) followColorScheme(this.previewEl);
    addClasses(classes, {
      // Every ASKING card's preview. Not this one's alone — the sheet is
      // shared, and scoping it to one id would style the first card that asked
      // and no other. And not every card's, because the sheet carries
      // Tailwind's preflight: a page that mixes one margaui card with eight
      // that style themselves would have the eight quietly restyled by their
      // neighbour.
      scope: "mb-card[margaui] .mbc-preview",
      styleId: "mb-card-margaui",
    });
  }

  drawIssues(issues) {
    this.issuesEl.replaceChildren();
    for (const issue of issues) {
      const li = document.createElement("li");
      const where = document.createElement("button");
      where.className = "mbc-where";
      where.type = "button";
      where.textContent = `line ${issue.line}`;
      // The span is in FILE coordinates, which is what the script block's
      // recorded offset is for: clicking a diagnostic selects the exact
      // characters it is about.
      where.addEventListener("click", () =>
        this.selectRange(issue.start, issue.end),
      );
      const code = document.createElement("code");
      code.textContent = issue.code ?? "";
      const msg = document.createElement("span");
      msg.textContent = issue.message;
      li.append(where, code, msg);
      this.issuesEl.append(li);
    }
  }
}

customElements.define("mb-card", MbCard);
