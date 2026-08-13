// The card playground's shell.
//
// Everything here is presentation. The whole edit loop is one call —
// `__tutucard.load(source, name)` — and the rest of this file draws what it
// answers. There is no worker, no compiler client, no payload manifest and no
// toolchain pin, because there is nothing to compile: a card is parsed and
// mounted, and the runtime that does it is already on the page.

import { EXAMPLES } from "./examples.js";
import { addClasses } from "./margaui.js";
import {
  addView,
  componentOf,
  dedented,
  parts,
  reindented,
  renameView,
  splice,
} from "./regions.js";

const $ = (id) => document.getElementById(id);
const els = {
  source: $("source"),
  gutter: $("gutter"),
  issues: $("issues"),
  state: $("state"),
  activity: $("activity"),
  status: $("status"),
  example: $("example"),
  raw: $("raw"),
  structured: $("structured"),
  part: $("part"),
  partEdit: $("part-edit"),
  partEmpty: $("part-empty"),
  viewTabs: $("view-tabs"),
};

/**
 * Which pane is showing, and which part of the card it is showing.
 *
 * The RAW editor holds the card; the structured panes are projections of the
 * same string. So there is one source of truth and no diffing: a structured
 * edit splices into `source()` and everything redraws from there.
 */
const ui = { mode: "raw", part: "state", view: 0 };

/** Debounce, so a fast typist re-mounts on pauses rather than per keystroke. */
const DEBOUNCE_MS = 180;

/** Lines the last load complained about, for the gutter. */
let markedLines = new Set();

// ---------------------------------------------------------------------------
// The editor
// ---------------------------------------------------------------------------

/**
 * CodeMirror, or the textareas the page loads with.
 *
 * The editor is the DEFAULT and it is fetched LATE, which is one decision, not
 * two: the bundle is ~330 KB — more than the runtime this page exists to be
 * small about — so the page ships a textarea that is editable on first paint
 * and upgrades it once the import lands. An import that fails leaves a working
 * editor and a line in the console.
 *
 * `?editor=plain` keeps the textareas: a page that fetches nothing, and the
 * first thing to try when the highlighting is what looks broken.
 */
const PLAIN = new URLSearchParams(location.search).get("editor") === "plain";

/** The two upgraded editors, once they exist: the raw card and the part pane. */
const cm = { source: null, part: null };

/** The factory, from the bundle. Null until the import lands, or forever. */
let createEditor = null;

/**
 * True while the shell is writing to an editor rather than the user.
 *
 * CodeMirror's change listener cannot tell the two apart, and every write here
 * comes from code that already knows what to do next — so a `setValue` from
 * `drawPart` must not read back as an edit and splice the pane's own text into
 * the card on every tab click.
 */
let echoing = false;

/**
 * The card being edited, and the one place that knows where it lives.
 *
 * Everything below goes through these four, so the upgrade is a swap of one
 * field rather than a second copy of the shell.
 */
function source() {
  return cm.source ? cm.source.getValue() : els.source.value;
}

function setSource(text) {
  echoing = true;
  try {
    if (cm.source) cm.source.setValue(text);
    else els.source.value = text;
  } finally {
    echoing = false;
  }
}

function partText() {
  return cm.part ? cm.part.getValue() : els.part.value;
}

function setPartText(text) {
  echoing = true;
  try {
    if (cm.part) cm.part.setValue(text);
    else els.part.value = text;
  } finally {
    echoing = false;
  }
}

/** Select the characters an issue is about, and show them. */
function selectRange(from, to) {
  if (cm.source) {
    cm.source.view.dispatch({
      selection: { anchor: from, head: to },
      scrollIntoView: true,
    });
    cm.source.focus();
    return;
  }
  els.source.focus();
  els.source.setSelectionRange(from, to);
}

/** Which language the part pane is holding, by which tab is showing. */
const partLang = () => (ui.part === "views" ? "html" : "tutuca");

/** The mode the part editor was last reconfigured to. */
let partLangNow = null;

/**
 * Swap the textareas for CodeMirror.
 *
 * The raw editor only; the part pane's is built the first time that pane is
 * SHOWN (`ensurePartEditor`), because CodeMirror measures itself when it is
 * constructed and one built inside a hidden pane comes up with no height.
 */
async function upgradeEditors() {
  if (PLAIN) return;
  try {
    ({ createEditor } = await import("./editor.bundle.js"));
  } catch (e) {
    console.warn(`[tutucard] CodeMirror unavailable: ${e.message}`);
    return;
  }
  cm.source = createEditor({
    parent: els.raw,
    doc: els.source.value,
    // A card is a view file: `lang: "html"` is the mode that knows a
    // directive from an attribute AND colours what the tutuca blocks hold.
    lang: "html",
    // This shell has ONE palette (see styleClasses), so the editor cannot be
    // allowed to follow an OS that says light.
    dark: true,
    // The textarea soft-wrapped, and this pane is a third of the page: a card
    // whose views carry class lists would otherwise be read sideways.
    wrap: true,
    onChange: () => {
      if (!echoing) scheduleReload();
    },
  });
  els.source.hidden = true;
  // The editor draws its own line numbers, and two gutters is one too many.
  // The dots move with them: an underline on the offending characters, which
  // is what the gutter dot was standing in for.
  els.gutter.hidden = true;
  markIssues(lastIssues);
  // The reader may have switched panes while the bundle was in flight, in
  // which case the part pane is on screen and this is its first chance.
  if (ui.mode === "structured") ensurePartEditor();
}

/** Build the part pane's editor, the first time that pane is shown. */
function ensurePartEditor() {
  if (cm.part || !createEditor) return;
  partLangNow = partLang();
  cm.part = createEditor({
    parent: els.partEdit,
    doc: els.part.value,
    lang: partLangNow,
    dark: true,
    wrap: true,
    onChange: () => {
      if (!echoing) onPartInput();
    },
  });
  els.part.hidden = true;
}

/**
 * The region text the structured pane last agreed with — what it was drawn
 * from, or what it last spliced in. Compared against rather than the pane's own
 * value because the pane holds a DEDENTED projection: re-deriving it on every
 * debounce would fight a typist who indents a line, so the pane is left alone
 * until the card changes underneath it.
 */
let paneEcho = null;

function componentName(source) {
  // The template's id names the component, when it has one. Otherwise the
  // state block's own name does, and failing both we pick something — `load`
  // only uses it as the fallback name.
  return componentOf(source) || "Card";
}

function drawGutter(text) {
  // CodeMirror numbers its own lines and marks its own issues, so the callers
  // that keep the count in step after an edit say so here rather than each
  // asking which editor is on the page.
  if (cm.source) return;
  const lines = text.split("\n").length;
  const out = [];
  for (let i = 1; i <= lines; i++) {
    out.push(markedLines.has(i) ? `${i} ●` : `${i}`);
  }
  els.gutter.textContent = out.join("\n");
}

/** What the last load complained about, for an editor that arrives after it. */
let lastIssues = [];

/**
 * Where the issues are, in the editor itself.
 *
 * Two channels for one fact, because the two editors can say it to different
 * depths: the hand-drawn gutter carries a dot on the line, and CodeMirror
 * underlines the exact characters and says why on hover. The list beside the
 * preview is the same set either way.
 */
function markIssues(issues) {
  lastIssues = issues;
  if (cm.source) {
    cm.source.setSpans(
      issues.map((i) => ({
        from: i.start,
        to: i.end,
        message: i.code ? `${i.code}: ${i.message}` : i.message,
        // A card that does not split or does not parse is an error; everything
        // the checker has to say about one that does is a warning.
        severity: i.code === "SYNTAX" ? "error" : "warning",
      })),
    );
    return;
  }
  markedLines = new Set(issues.map((i) => i.line));
  drawGutter(source());
}

function drawIssues(issues) {
  els.issues.replaceChildren();
  if (issues.length === 0) {
    const li = document.createElement("li");
    li.className = "ok";
    li.textContent = "no issues";
    els.issues.append(li);
    return;
  }
  for (const issue of issues) {
    const li = document.createElement("li");
    li.className = "issue";
    const where = document.createElement("button");
    where.className = "where";
    where.textContent = `line ${issue.line}`;
    // The span is in FILE coordinates, which is the whole reason the script
    // block records where it started: clicking a diagnostic selects the exact
    // characters it is about.
    where.addEventListener("click", () => selectRange(issue.start, issue.end));
    const code = document.createElement("code");
    code.textContent = issue.code ?? "";
    const msg = document.createElement("span");
    msg.textContent = issue.message;
    li.append(where, code, msg);
    els.issues.append(li);
  }
}

function drawState() {
  try {
    els.state.textContent = JSON.stringify(
      JSON.parse(globalThis.__tutucard.state()),
      null,
      2,
    );
  } catch {
    els.state.textContent = "—";
  }
}

function drawActivity() {
  let records = [];
  try {
    records = JSON.parse(globalThis.__tutucard.activity());
  } catch {
    /* the panel is a convenience; a bad read is not worth a failure */
  }
  els.activity.replaceChildren();
  for (const r of records.slice(-40)) {
    const li = document.createElement("li");
    const kind = document.createElement("code");
    kind.textContent = r.kind ?? "?";
    const name = document.createElement("b");
    name.textContent = r.name ?? "";
    const matched = document.createElement("span");
    matched.className = r.matched === "no-handler" ? "miss" : "hit";
    matched.textContent = r.matched ?? "";
    li.append(kind, name, matched);
    els.activity.append(li);
  }
}

/** Parse, check, mount, and draw everything that came back. */
function reload() {
  // A pending debounce would re-mount, half a beat later, the card this call
  // is mounting now — and re-mounting resets the app the reader may already
  // have clicked. Callers that mount immediately (a new example, a reset) do
  // not have to remember to cancel it.
  clearTimeout(timer);
  const src = source();
  const report = JSON.parse(
    globalThis.__tutucard.load(src, componentName(src)),
  );
  let issues;
  if (!report.ok) {
    // Nothing to mount: the file does not split, or the script does not parse.
    // The last render STAYS, dimmed, rather than blanking — a syntax error is
    // the ordinary state of a half-typed line, and a preview that goes empty
    // between two keystrokes is worse than one that is visibly behind. The
    // class is what says it is behind; the app itself is already torn down.
    els.status.textContent = "cannot load";
    els.status.className = "status bad";
    $("preview").classList.add("stale");
    issues = [
      {
        line: report.line,
        code: "SYNTAX",
        // The loader's message names its own line, because it is also what a
        // CLI would print. The gutter button says that here, so drop it.
        message: report.error.replace(/^line \d+: /, ""),
        start: report.start,
        end: report.end,
      },
    ];
  } else {
    $("preview").classList.remove("stale");
    issues = report.issues;
    const n = report.issues.length;
    els.status.textContent =
      n === 0 ? `${report.component} · ok` : `${report.component} · ${n} issue${n === 1 ? "" : "s"}`;
    els.status.className = n === 0 ? "status good" : "status warn";
  }
  drawIssues(issues);
  markIssues(issues);
  drawState();
  drawActivity();
  styleClasses();
}

/**
 * Compile the mounted card's class names with margaui and inject the CSS.
 *
 * Unconditional here, unlike `<mb-card margaui>`: this is the tool, its
 * starter cards are written in margaui's component classes, and a card that
 * says `class="btn btn-primary"` and renders as an unstyled button is a
 * playground lying about what a card can look like. The ~0.5 MB compiler is
 * still fetched lazily — on the first mount that publishes a class name, which
 * is the first mount.
 *
 * Scoped to the preview pane, because this page has a UI of its own: margaui's
 * sheet carries Tailwind's preflight, and unscoped it would flatten the
 * editor, the tabs and the panels around the card.
 */
function styleClasses() {
  let classes = [];
  try {
    classes = JSON.parse(globalThis.__tutucard.classes());
  } catch {
    return;
  }
  if (classes.length) {
    // Dark, always: margaui picks its theme off `data-theme`, and this shell
    // has ONE palette rather than a light and a dark one. A preview that
    // followed the reader's OS instead would be a white card sitting in a dark
    // tool half the time. An `<mb-card>` embedded in a page that does have both
    // follows the page (`followColorScheme` in web/margaui.js).
    $("preview").dataset.theme = "dark";
    addClasses(classes, { scope: "#preview", styleId: "card-margaui" });
  }
}

let timer = null;
function scheduleReload() {
  clearTimeout(timer);
  timer = setTimeout(() => {
    reload();
    // The structured tabs follow the card, so a raw edit that adds a view
    // makes the tab appear — on the same debounce, because retitling tabs per
    // keystroke is the one thing more distracting than a preview that lags.
    drawTabs();
  }, DEBOUNCE_MS);
}

// ---------------------------------------------------------------------------
// The structured view
// ---------------------------------------------------------------------------

/** The region the structured view is currently editing, or null. */
function currentRegion() {
  const p = parts(source());
  if (ui.part === "state") return p.state;
  if (ui.part === "script") return p.script;
  return p.views[Math.min(ui.view, p.views.length - 1)] ?? null;
}

/** What to say when the part the tab names is not in the card yet. */
const MISSING = {
  state: 'no <script type="tutuca/state"> block yet — add one in the raw view',
  script:
    'no <script type="tutuca/script"> block yet — add one in the raw view',
  views: "no <template> yet",
};

/** Put the current part in the pane. */
function drawPart() {
  const region = currentRegion();
  els.viewTabs.hidden = ui.part !== "views";
  if (!region) {
    els.partEdit.hidden = true;
    els.partEmpty.hidden = false;
    els.partEmpty.textContent = MISSING[ui.part];
    return;
  }
  els.partEmpty.hidden = true;
  const wasHidden = els.partEdit.hidden;
  els.partEdit.hidden = false;
  // The state and script blocks are one language and a view is another, so the
  // pane's mode follows its tabs. Only on a change: this runs on the same
  // debounce as the reload, and a reconfigure per keystroke would be work
  // nobody asked for.
  if (cm.part && partLangNow !== partLang()) {
    partLangNow = partLang();
    cm.part.setLang(partLangNow);
  }
  // CodeMirror sizes itself against a box it can see, and this one may have
  // just come back from `display: none`.
  if (wasHidden) cm.part?.view.requestMeasure();
  // Only when it CHANGED: assigning the value moves the caret to the end, and
  // this runs on the same debounce as the reload — so a typist would be
  // fighting it. A raw edit, another tab or a new example changes the region
  // out from under the pane; an edit made HERE does not redraw the pane it
  // came from.
  if (region.text !== paneEcho) {
    setPartText(dedented(region.text));
    paneEcho = region.text;
  }
}

/** The view tabs, `main` first. */
function drawTabs() {
  const p = parts(source());
  if (ui.view >= p.views.length) ui.view = Math.max(0, p.views.length - 1);
  els.viewTabs.replaceChildren();
  p.views.forEach((v, i) => {
    const b = document.createElement("button");
    b.className = i === ui.view ? "tab on" : "tab";
    b.textContent = v.name;
    b.role = "tab";
    b.addEventListener("click", () => {
      ui.view = i;
      drawTabs();
      drawPart();
    });
    // `main` is the view every card has and the one it mounts with, so it is
    // the only name that is not the author's to change.
    b.addEventListener("dblclick", () => {
      if (v.name === "main") return;
      const name = prompt("view name", v.name);
      if (!name || name === v.name) return;
      setSource(renameView(source(), p, i, name));
      drawTabs();
      drawGutter(source());
      scheduleReload();
    });
    els.viewTabs.append(b);
  });
  const add = document.createElement("button");
  add.className = "tab add";
  add.textContent = "+";
  add.title = "add a view";
  add.addEventListener("click", () => {
    const name = prompt("new view name", `view${p.views.length}`);
    if (!name) return;
    setSource(addView(source(), name));
    ui.view = parts(source()).views.length - 1;
    drawTabs();
    drawPart();
    drawGutter(source());
    scheduleReload();
  });
  els.viewTabs.append(add);
}

/** Show one mode, hide the other. Both read the same string. */
function setMode(mode) {
  ui.mode = mode;
  els.raw.hidden = mode !== "raw";
  els.structured.hidden = mode !== "structured";
  $("mode-raw").classList.toggle("on", mode === "raw");
  $("mode-structured").classList.toggle("on", mode === "structured");
  $("mode-raw").ariaSelected = String(mode === "raw");
  $("mode-structured").ariaSelected = String(mode === "structured");
  if (mode === "structured") {
    drawTabs();
    drawPart();
    // After the pane is filled and visible, so the editor is built once with
    // the text it is going to hold and a box it can measure.
    ensurePartEditor();
  } else {
    drawGutter(source());
    cm.source?.view.requestMeasure();
  }
}

/** Show one part of the card. */
function setPart(part) {
  ui.part = part;
  for (const b of els.structured.querySelectorAll(".tabs:not(.views) .tab")) {
    b.classList.toggle("on", b.dataset.part === part);
  }
  if (part === "views") drawTabs();
  drawPart();
}

/** A structured edit, spliced back into the one string that is the card. */
function onPartInput() {
  const region = currentRegion();
  if (!region) return;
  const text = reindented(region.text, partText());
  paneEcho = text;
  setSource(splice(source(), region, text));
  scheduleReload();
}

function pickExample(name) {
  const ex = EXAMPLES.find((e) => e.name === name) ?? EXAMPLES[0];
  setSource(ex.source);
  ui.view = 0;
  reload();
  if (ui.mode === "structured") {
    drawTabs();
    drawPart();
  }
}

function boot() {
  for (const ex of EXAMPLES) {
    const opt = document.createElement("option");
    opt.value = ex.name;
    opt.textContent = ex.name;
    els.example.append(opt);
  }
  els.example.addEventListener("change", () => pickExample(els.example.value));
  els.source.addEventListener("input", scheduleReload);
  els.part.addEventListener("input", onPartInput);
  $("mode-raw").addEventListener("click", () => setMode("raw"));
  $("mode-structured").addEventListener("click", () => setMode("structured"));
  for (const b of els.structured.querySelectorAll(".tabs:not(.views) .tab")) {
    b.addEventListener("click", () => setPart(b.dataset.part));
  }
  // The preview is a live app: interacting with it changes state and raises
  // dispatches, and both panels should follow. A capture-phase listener sees
  // the event before the app's delegated one, so the redraw is queued after.
  els.source.addEventListener("scroll", () => {
    els.gutter.scrollTop = els.source.scrollTop;
  });
  $("preview").addEventListener(
    "click",
    () => setTimeout(() => {
      drawState();
      drawActivity();
    }, 0),
    true,
  );
  $("preview").addEventListener(
    "input",
    () => setTimeout(() => {
      drawState();
      drawActivity();
    }, 0),
    true,
  );
  pickExample(EXAMPLES[0].name);
  // Last, and not awaited: the page is a working playground by the time the
  // editor is asked for, so the 330 KB lands on a card that is already mounted
  // and typeable rather than in front of it.
  upgradeEditors();
}

if (globalThis.__tutucard) {
  boot();
} else {
  // The MoonBit bundle installs the entry points when it loads, and a module
  // script runs after a classic one — but say so rather than failing blank if
  // that ever stops being true.
  els.status.textContent = "runtime did not load";
  els.status.className = "status bad";
}
