// Shared CodeMirror 6 editor for the tutuca-mb playgrounds. Exposes one
// createEditor() factory used by both the full playground (playground/web/
// driver.js) and the embeddable <mb-playground> element (playground/site/
// embed.js), so there is a single seam for the editor behind both. Bundled to
// dist/playground/editor.bundle.js by playground/build/assemble.mjs (esbuild).
//
// Highlighting uses a lightweight StreamLanguage MoonBit mode — no external
// grammar and no onig.wasm, unlike moonpad's Monaco+TextMate path. StreamLanguage
// resolves the string a token() call returns directly as a @lezer/highlight tag
// name (its default token table is empty), so we return tag names like "keyword"
// and colour them via the HighlightStyle below.

import { Compartment } from "@codemirror/state";
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

// exported for headless token tests; the editor uses moonbit() below
export { moonbitMode };
function moonbit() {
  return new LanguageSupport(moonbitMode);
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

// createEditor({ parent, doc?, onRun?, onChange?, root? }) → editor handle.
// `root` lets callers hosting the editor inside a shadow root (the embeddable
// element) tell CodeMirror where to find its DOM. onRun fires on Mod-Enter.
export function createEditor({ parent, doc = "", onRun, onChange, root } = {}) {
  const theme = new Compartment();
  const extensions = [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightActiveLine(),
    history(),
    drawSelection(),
    indentUnit.of("  "),
    indentOnInput(),
    bracketMatching(),
    moonbit(),
    theme.of(themeExtensions(prefersDark())),
    keymap.of([
      ...(onRun ? [{ key: "Mod-Enter", preventDefault: true, run: () => { onRun(); return true; } }] : []),
      indentWithTab,
      ...defaultKeymap,
      ...historyKeymap,
    ]),
  ];
  if (onChange) {
    extensions.push(EditorView.updateListener.of((u) => {
      if (u.docChanged) onChange(u.state.doc.toString());
    }));
  }

  const view = new EditorView({ parent, root, doc, extensions });

  // follow OS light/dark changes live
  let mql = null, onScheme = null;
  if (typeof matchMedia === "function") {
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
    focus: () => view.focus(),
    destroy: () => {
      if (mql && onScheme) mql.removeEventListener("change", onScheme);
      view.destroy();
    },
  };
}
