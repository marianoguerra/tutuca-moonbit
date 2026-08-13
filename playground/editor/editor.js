// Shared CodeMirror 6 editor for the tutuca-mb playgrounds. Exposes one
// createEditor() factory used by the full playground (playground/web/
// driver.js), the embeddable <mb-playground> element (playground/site/
// embed.js) and <mb-card codemirror> (tutucard/web/card-embed.js), so there is
// a single seam for the editor behind all three. Bundled by esbuild to
// dist/playground/editor.bundle.js (playground/build/assemble.mjs) and to
// dist/tutucard/editor.bundle.js (tutucard/build/assemble.mjs) — the card
// payload stands on its own, so it bundles rather than borrows.
//
// Highlighting uses a lightweight StreamLanguage MoonBit mode — no external
// grammar and no onig.wasm, unlike moonpad's Monaco+TextMate path. StreamLanguage
// resolves the string a token() call returns directly as a @lezer/highlight tag
// name (its default token table is empty), so we return tag names like "keyword"
// and colour them via the HighlightStyle below.

import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, drawSelection } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { StreamLanguage, HighlightStyle, syntaxHighlighting, LanguageSupport, indentUnit, bracketMatching, indentOnInput } from "@codemirror/language";
import { setDiagnostics as setLintDiagnostics } from "@codemirror/lint";
import { tags } from "@lezer/highlight";

// --- MoonBit mode -----------------------------------------------------------

const KEYWORDS = new Set([
  "fn", "let", "mut", "type", "typealias", "struct", "enum", "trait", "impl",
  "derive", "pub", "priv", "readonly", "extern", "const", "if", "else", "while",
  "for", "in", "match", "loop", "return", "break", "continue", "raise", "try",
  "catch", "guard", "as", "is", "with", "and", "test", "self", "init", "main",
  "async", "defer", "then", "throw", "throws", "using", "fnalias", "letrec",
]);

// consume a "…" string body (single line — MoonBit spans lines with #| / $|)
function tokenString(stream, state) {
  let escaped = false, ch;
  while ((ch = stream.next()) != null) {
    if (ch === '"' && !escaped) break;
    escaped = !escaped && ch === "\\";
  }
  state.tokenize = null; // never spans lines
  return "string";
}

function baseToken(stream, state) {
  if (stream.eatSpace()) return null;

  // multiline / interpolated string lines: #|…  and  $|…
  if (stream.match(/^[#$]\|.*/)) return "string";

  const ch = stream.peek();

  // comments — /// doc, // line
  if (stream.match(/^\/\/.*/)) return "comment";

  // char literal: 'a' or '\n'
  if (ch === "'" && stream.match(/^'(?:\\.|[^'\\])'/)) return "string";

  // string
  if (ch === '"') {
    stream.next();
    state.tokenize = tokenString;
    return tokenString(stream, state);
  }

  // numbers: 0x.. 0o.. 0b.. decimals/floats with _ separators and suffixes
  if (stream.match(/^0[xX][0-9a-fA-F_]+/) ||
      stream.match(/^0[oO][0-7_]+/) ||
      stream.match(/^0[bB][01_]+/) ||
      stream.match(/^\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?[a-zA-Z]*/) ||
      stream.match(/^\.\d[\d_]*(?:[eE][+-]?\d+)?/)) {
    return "number";
  }

  // package qualifier: @pkg
  if (stream.match(/^@[A-Za-z_][A-Za-z0-9_]*/)) return "namespace";

  // identifiers / keywords / types
  const m = stream.match(/^[A-Za-z_][A-Za-z0-9_]*/);
  if (m) {
    const w = m[0];
    if (w === "true" || w === "false") return "bool";
    if (KEYWORDS.has(w)) return "keyword";
    if (/^[A-Z]/.test(w)) return "typeName";
    return "variableName";
  }

  // operators
  if (stream.match(/^[+\-*/%=<>!&|^~?:.]+/)) return "operator";

  // punctuation / anything else — leave default coloured
  stream.next();
  return null;
}

const moonbitMode = StreamLanguage.define({
  name: "moonbit",
  startState: () => ({ tokenize: null }),
  token(stream, state) {
    return (state.tokenize || baseToken)(stream, state);
  },
  languageData: { commentTokens: { line: "//" } },
});

// --- tutuca block language --------------------------------------------------
// What a <script type="tutuca/state"> or "tutuca/script" block holds. It is
// not HTML and it is not MoonBit — it is the small language `tscript` parses,
// and its atoms are the view's atoms (`.field`, `@bind`, `$method`, `*dyn`,
// `'text'`), which is exactly why they are coloured the same here.
//
// A card is mostly these blocks, so a view file highlighted without them is a
// file with its middle greyed out.

const BLOCK_KEYWORDS = new Set([
  // declarations
  "on", "receive", "bubble", "response", "compute", "pred", "enrich",
  "enrichScope",
  // the schema's own
  "state", "struct", "enum",
  // statements and effects
  "if", "else", "send", "request", "sendAt", "stop",
  // operators that are words
  "and", "or", "not", "is", "implies", "mod",
]);

function blockToken(stream, state) {
  // The closing tag ends the block and hands the stream back to the tag
  // tokenizer, which is mid-tag by the time it sees `>`.
  if (stream.match(/^<\/script/i)) {
    state.tokenize = null;
    state.inTag = true;
    return "tagName";
  }
  if (stream.eatSpace()) return null;
  if (stream.match(/^\/\/.*/)) return "comment";
  // `$'…{expr}…'` and `'…'` are one token: the interpolations inside a
  // template are expressions, but colouring them apart buys less than it
  // costs in a mode this size.
  if (stream.match(/^\$?'(?:[^'\\]|\\.)*'?/)) return "string";
  // A place or a binding, with `&` for the reference form `sendAt` takes.
  if (stream.match(/^&?[.@$*][\w-]+/)) return "variableName";
  if (stream.match(/^-?\d+(?:\.\d+)?/)) return "number";
  const word = stream.match(/^[A-Za-z_][\w?]*/);
  if (word) {
    const w = word[0];
    if (w === "true" || w === "false") return "bool";
    if (BLOCK_KEYWORDS.has(w)) return "keyword";
    // `empty?`, `len`, `clamp` — the closed reading vocabulary, and the
    // schema's type names, both of which read as names rather than syntax.
    if (/^[A-Z]/.test(w)) return "typeName";
    return null;
  }
  if (stream.match(/^(?:\+=|-=|[=+\-*/<>]|is not)/)) return "operator";
  stream.next();
  return null;
}

// --- tutuca view mode ------------------------------------------------------
// The View tab holds tutuca's HTML-ish template syntax, so plain HTML
// highlighting would miss what actually matters: which attributes are
// directives (@on.click, @each, @if.class), which are dynamic bindings
// (:value), and where a value expression sits. Same StreamLanguage approach as
// the MoonBit mode — token() returns @lezer/highlight tag names directly.
const viewMode = StreamLanguage.define({
  name: "tutuca-view",
  startState: () => ({ inTag: false, tokenize: null, script: false }),
  token(stream, state) {
    if (state.tokenize) return state.tokenize(stream, state);
    if (stream.eatSpace()) return null;
    if (stream.match(/^<!--/)) {
      state.tokenize = (st, s2) => {
        if (st.match(/^[\s\S]*?-->/)) s2.tokenize = null;
        else st.skipToEnd();
        return "comment";
      };
      return state.tokenize(stream, state);
    }
    if (!state.inTag) {
      const open = stream.match(/^<\/?[A-Za-z][\w:.-]*/);
      if (open) {
        state.inTag = true;
        // Remembered rather than acted on: what follows the tag name is still
        // attributes, and the block only starts at the `>`.
        state.script = /^<script$/i.test(open[0]);
        return "tagName";
      }
      if (stream.match(/^&[#\w]+;/)) return "string";
      stream.next();
      stream.eatWhile((c) => c !== "<" && c !== "&");
      return null;
    }
    // inside a tag
    const close = stream.match(/^\/?>/);
    if (close) {
      state.inTag = false;
      // `<script … />` closes itself and holds nothing, so only a plain `>`
      // opens a block.
      if (state.script && close[0] === ">") {
        state.tokenize = blockToken;
      }
      state.script = false;
      return "tagName";
    }
    // directive (@on.click, @each, @if.class, @text) or dynamic bind (:value)
    if (stream.match(/^[@:][\w.+-]+/)) return "keyword";
    if (stream.match(/^[A-Za-z][\w:.-]*/)) return "propertyName";
    if (stream.match(/^=/)) return "operator";
    if (stream.match(/^"/)) {
      state.tokenize = (st, s2) => {
        // a value expression: highlight its sigils inside the quotes
        if (st.match(/^"/)) { s2.tokenize = null; return "string"; }
        if (st.match(/^[.$*][\w-]+/)) return "variableName";
        if (st.match(/^@[\w.-]+/)) return "variableName";
        if (st.match(/^'(?:[^'\\]|\\.)*'/)) return "literal";
        if (st.match(/^-?\d+(?:\.\d+)?/)) return "number";
        st.next();
        st.eatWhile((c) => c !== '"' && c !== "." && c !== "$" && c !== "@" && c !== "*" && c !== "'");
        return "string";
      };
      return "string";
    }
    stream.next();
    return null;
  },
  languageData: { commentTokens: { block: { open: "<!--", close: "-->" } } },
});

///|
function viewHtml() {
  return new LanguageSupport(viewMode);
}

// The block language on its own, for a pane holding ONE block's body rather
// than a whole file: the card playground's structured view edits the state and
// script regions WITHOUT the `<script>` tags around them, and the view mode
// only ever reaches blockToken through a tag that pane cannot see.
const blockMode = StreamLanguage.define({
  name: "tutuca-block",
  startState: () => ({ inTag: false, tokenize: null }),
  token(stream, state) {
    return (state.tokenize || blockToken)(stream, state);
  },
  languageData: { commentTokens: { line: "//" } },
});

// exported for headless token tests; the editor uses langFor()
export { moonbitMode, viewMode, blockMode };
function moonbit() {
  return new LanguageSupport(moonbitMode);
}

/** The mode a pane asks for by name. MoonBit unless it says otherwise. */
function langFor(lang) {
  if (lang === "html") return viewHtml();
  if (lang === "tutuca") return new LanguageSupport(blockMode);
  return moonbit();
}

// --- highlight themes -------------------------------------------------------
// Two palettes; the active one follows the OS prefers-color-scheme (see the
// theme compartment in createEditor). Backgrounds are transparent so the editor
// blends into whatever surface hosts it (the page chrome carries its own
// light/dark styling).

const lightHighlight = HighlightStyle.define([
  { tag: tags.comment, color: "#6e7781", fontStyle: "italic" },
  { tag: tags.keyword, color: "#cf222e" },
  { tag: tags.bool, color: "#0550ae" },
  { tag: tags.number, color: "#0550ae" },
  { tag: tags.string, color: "#0a3069" },
  { tag: tags.typeName, color: "#953800" },
  { tag: tags.namespace, color: "#6639ba" },
  { tag: tags.operator, color: "#0550ae" },
  { tag: tags.variableName, color: "#24292f" },
]);

const darkHighlight = HighlightStyle.define([
  { tag: tags.comment, color: "#8b949e", fontStyle: "italic" },
  { tag: tags.keyword, color: "#ff7b72" },
  { tag: tags.bool, color: "#79c0ff" },
  { tag: tags.number, color: "#79c0ff" },
  { tag: tags.string, color: "#a5d6ff" },
  { tag: tags.typeName, color: "#ffa657" },
  { tag: tags.namespace, color: "#d2a8ff" },
  { tag: tags.operator, color: "#79c0ff" },
  { tag: tags.variableName, color: "#c9d1d9" },
]);

const MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";

const lightTheme = EditorView.theme({
  "&": { height: "100%", fontSize: "12.5px", color: "#24292f", backgroundColor: "transparent" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: MONO, lineHeight: "1.55" },
  ".cm-gutters": { backgroundColor: "transparent", border: "none", color: "#8c959f" },
  ".cm-content": { padding: "0.6rem 0" },
});

const darkTheme = EditorView.theme({
  "&": { height: "100%", fontSize: "12.5px", color: "#c9d1d9", backgroundColor: "transparent" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: MONO, lineHeight: "1.55" },
  ".cm-gutters": { backgroundColor: "transparent", border: "none", color: "#6e7681" },
  ".cm-content": { padding: "0.6rem 0" },
  ".cm-activeLine": { backgroundColor: "rgba(255,255,255,0.04)" },
  ".cm-activeLineGutter": { backgroundColor: "rgba(255,255,255,0.05)" },
  ".cm-cursor": { borderLeftColor: "#c9d1d9" },
}, { dark: true });

function themeExtensions(dark) {
  return dark ? [darkTheme, syntaxHighlighting(darkHighlight)] : [lightTheme, syntaxHighlighting(lightHighlight)];
}

const prefersDark = () =>
  typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches;

// --- diagnostics ------------------------------------------------------------
// moonc human diagnostics look like:
//   ./main.mbt:2:11-2:24 [E4021] The value identifier x is unbound.
// (1-based line/col, end column is exclusive). Map each to a CodeMirror lint
// Diagnostic so the editor underlines the offending span with a hover message.

const DIAG_RE = /^(?:[^\s:]+):(\d+):(\d+)-(\d+):(\d+)\s+(.*)$/s;

function posAt(doc, line, col) {
  const l = doc.line(Math.min(Math.max(line, 1), doc.lines));
  return Math.min(l.from + Math.max(0, col - 1), l.to);
}

// Diagnostics from spans the caller already holds. A card's loader answers
// with character offsets into the file it was handed, so there is nothing to
// parse — and nothing to re-encode into moonc's text shape just to have
// parseDiagnostics read it back out.
function spanDiagnostics(spans, doc) {
  const out = [];
  for (const s of spans || []) {
    const from = Math.min(Math.max(s.from | 0, 0), doc.length);
    let to = Math.min(Math.max(s.to | 0, from), doc.length);
    // A zero-width span underlines nothing, so widen it by a character where
    // there is one — the card loader reports an empty range at end-of-file.
    if (to <= from) to = Math.min(from + 1, doc.length);
    out.push({
      from,
      to,
      severity: s.severity || "warning",
      message: s.message || "",
    });
  }
  return out.sort((a, b) => a.from - b.from || a.to - b.to);
}

function parseDiagnostics(raw, doc) {
  const out = [];
  for (const entry of raw || []) {
    const m = DIAG_RE.exec(String(entry).trim());
    if (!m) continue;
    const [, sl, sc, el, ec, message] = m;
    const from = posAt(doc, +sl, +sc);
    let to = posAt(doc, +el, +ec);
    if (to <= from) to = Math.min(from + 1, doc.length);
    const isError = /\[E\d/.test(message) && !/warning/i.test(message);
    out.push({ from, to, severity: isError ? "error" : "warning", message: message.replace(/\s+/g, " ").trim() });
  }
  return out.sort((a, b) => a.from - b.from || a.to - b.to);
}

// --- factory ----------------------------------------------------------------

// createEditor({ parent, doc?, onRun?, onChange?, root?, readOnly?, lang?,
// dark?, wrap? }) → editor handle. `root` lets callers hosting the editor inside a
// shadow root (the embeddable element) tell CodeMirror where to find its DOM.
// onRun fires on Mod-Enter. `readOnly` is for panes the user reads but does not
// author — the playground's generated-module tab. `lang` picks the mode:
// "html" for a view file, "tutuca" for one block's body, anything else
// MoonBit. `dark` PINS the palette for a host that has only one — the card
// playground's shell is dark whatever the OS says, and light highlighting on
// its panels would be unreadable; left out, the theme follows the OS and keeps
// following it. `wrap` soft-wraps long lines instead of scrolling sideways, for
// a pane too narrow to read a class list in.
export function createEditor({ parent, doc = "", onRun, onChange, root, readOnly = false, lang, dark, wrap = false } = {}) {
  const theme = new Compartment();
  const language = new Compartment();
  const extensions = [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightActiveLine(),
    history(),
    drawSelection(),
    indentUnit.of("  "),
    indentOnInput(),
    bracketMatching(),
    language.of(langFor(lang)),
    theme.of(themeExtensions(dark ?? prefersDark())),
    keymap.of([
      ...(onRun ? [{ key: "Mod-Enter", preventDefault: true, run: () => { onRun(); return true; } }] : []),
      indentWithTab,
      ...defaultKeymap,
      ...historyKeymap,
    ]),
  ];
  if (wrap) {
    extensions.push(EditorView.lineWrapping);
  }
  if (readOnly) {
    extensions.push(EditorState.readOnly.of(true), EditorView.editable.of(false));
  }
  if (onChange) {
    extensions.push(EditorView.updateListener.of((u) => {
      if (u.docChanged) onChange(u.state.doc.toString());
    }));
  }

  const view = new EditorView({ parent, root, doc, extensions });

  // follow OS light/dark changes live — unless the caller pinned a palette
  let mql = null, onScheme = null;
  if (dark == null && typeof matchMedia === "function") {
    mql = matchMedia("(prefers-color-scheme: dark)");
    onScheme = (e) => view.dispatch({ effects: theme.reconfigure(themeExtensions(e.matches)) });
    mql.addEventListener("change", onScheme);
  }

  return {
    view,
    getValue: () => view.state.doc.toString(),
    setValue: (text) =>
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } }),
    // Show compiler diagnostics inline (underlines + hover). Pass moonc's raw
    // human-format strings; call with [] (or nothing) to clear them.
    setDiagnostics: (raw) =>
      view.dispatch(setLintDiagnostics(view.state, parseDiagnostics(raw, view.state.doc))),
    // The same underlines from spans the caller already has:
    // [{ from, to, message, severity? }] in character offsets.
    setSpans: (spans) =>
      view.dispatch(setLintDiagnostics(view.state, spanDiagnostics(spans, view.state.doc))),
    // Swap the mode — for a pane that holds a different language depending on
    // which tab is showing.
    setLang: (next) =>
      view.dispatch({ effects: language.reconfigure(langFor(next)) }),
    focus: () => view.focus(),
    destroy: () => {
      if (mql && onScheme) mql.removeEventListener("change", onScheme);
      view.destroy();
    },
  };
}
