// The card playground's shell.
//
// Everything here is presentation. The whole edit loop is one call —
// `mountCard(previewId, source, name)` — and the rest of this file draws what it
// answers. There is no worker, no compiler client, no payload manifest and no
// toolchain pin — the card compiler is a library in the bundle already on the
// page, so showing a card is compiling it to wasm and instantiating the module
// right here.

import { EXAMPLES } from "./examples.js";
import { addClasses } from "./margaui.js";
import {
  addMacro,
  addView,
  componentOf,
  dedented,
  parts,
  reindented,
  renameMacro,
  renameView,
  splice,
} from "./regions.js";

const $ = (id) => document.getElementById(id);
const els = {
  source: $("source"),
  gutter: $("gutter"),
  issues: $("issues"),
  compiled: $("compiled"),
  refusals: $("refusals"),
  wasmSize: $("wasm-size"),
  download: $("download"),
  load: $("load"),
  loaded: $("loaded"),
  loadedNote: $("loaded-note"),
  loadedIssues: $("loaded-issues"),
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
const ui = { mode: "raw", part: "state", view: 0, macro: 0 };

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
const partLang = () =>
  ui.part === "views" || ui.part === "macros" ? "html" : "tutuca";

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

/**
 * Check, compile, mount, and draw everything that came back.
 *
 * ASYNC, and it did not use to be: mounting a card meant handing its source to
 * an interpreter, and it now means compiling it to wasm and instantiating the
 * module. `mountCard` is the three steps and `WebAssembly.compile` is the
 * middle one — the only thing on this boundary that could not stay a
 * synchronous MoonBit call.
 *
 * One consequence worth naming: two reloads can now overlap, because a fast
 * typist can start a second while the first is still instantiating. `gen` is
 * what tells a late answer from a live one, and dropping a stale one is what
 * stops the older card from being the one left on the page.
 */
// The escape hatch is on in THIS page and off by default in the library, and
// the difference is the whole point of it being a parameter: a playground is a
// tool you point at your own card, so the code in it is yours. A page that
// mounts cards it did not write should pass false.
const ALLOW_WAX = true;

let reloadGen = 0;

async function reload() {
  // A pending debounce would re-mount, half a beat later, the card this call
  // is mounting now — and re-mounting resets the app the reader may already
  // have clicked. Callers that mount immediately (a new example, a reset) do
  // not have to remember to cancel it.
  clearTimeout(timer);
  const gen = ++reloadGen;
  const src = source();
  const { mountCard } = await import("./card-wasm.js");
  const report = await mountCard("preview", src, componentName(src), {
    allowWax: ALLOW_WAX,
  });
  if (gen !== reloadGen) return;
  let issues;
  if (!report.ok) {
    // Nothing to mount: the file does not split, or the script does not parse.
    // The last render STAYS, dimmed, rather than blanking — a syntax error is
    // the ordinary state of a half-typed line, and a preview that goes empty
    // between two keystrokes is worse than one that is visibly behind.
    els.status.textContent = "cannot load";
    els.status.className = "status bad";
    $("preview").classList.add("stale");
    issues = [
      {
        line: report.line,
        code: "SYNTAX",
        // The message names its own line, because it is also what a CLI would
        // print. The gutter button says that here, so drop it.
        message: String(report.error).replace(/^line \d+: /, ""),
        start: report.start,
        end: report.end,
      },
    ];
  } else if (!report.mounted && report.error) {
    // It checked, and then the compiler or the host turned it away. A different
    // failure from a card that does not parse, and worth a different sentence.
    els.status.textContent = "cannot compile";
    els.status.className = "status bad";
    $("preview").classList.add("stale");
    issues = [
      { line: 1, code: "COMPILE", message: String(report.error), start: 0, end: 0 },
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
  // The compile PANEL, from the build this mount already did — so the WAT, the
  // WAX and the download come from the module on the page rather than from a
  // second compile of the same source.
  showBuild(report.build);
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
  const list = listOf(p);
  return list.items[Math.min(list.index, list.items.length - 1)] ?? null;
}

/** What to say when the part the tab names is not in the card yet. */
const MISSING = {
  state: 'no <script type="tutuca/state"> block yet — add one in the raw view',
  script:
    'no <script type="tutuca/script"> block yet — add one in the raw view',
  views: "no <template> yet",
  macros: "no <template id=\"macro:…\"> yet — a macro is markup this file can call by name",
};

/** Put the current part in the pane. */
function drawPart() {
  const region = currentRegion();
  els.viewTabs.hidden = ui.part !== "views" && ui.part !== "macros";
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

/**
 * Which list the sub-tab bar is over, and the four things that differ between
 * them: where the index lives, what a new one is called, and the two splices.
 *
 * Views and macros are the same tab bar over two lists — a card has as many of
 * each as it likes, against one state block and one script block — so the only
 * honest way to draw both is to name what differs and share the rest.
 */
function listOf(p) {
  if (ui.part === "macros") {
    return {
      items: p.macros,
      index: ui.macro,
      select: (i) => {
        ui.macro = i;
      },
      what: "macro",
      // A macro's name is entirely the author's: nothing mounts a macro, so
      // there is no `main` to protect.
      fixed: () => false,
      rename: (src, i, name) => renameMacro(src, p, i, name),
      add: (src, name) => addMacro(src, name),
      count: (src) => parts(src).macros.length,
    };
  }
  return {
    items: p.views,
    index: ui.view,
    select: (i) => {
      ui.view = i;
    },
    what: "view",
    // `main` is the view every card has and the one it mounts with, so it is
    // the only name that is not the author's to change.
    fixed: (v) => v.name === "main",
    rename: (src, i, name) => renameView(src, p, i, name),
    add: (src, name) => addView(src, name),
    count: (src) => parts(src).views.length,
  };
}

/** The sub-tabs of whichever list is showing, `main` first for views. */
function drawTabs() {
  const p = parts(source());
  const list = listOf(p);
  if (list.index >= list.items.length) {
    list.select(Math.max(0, list.items.length - 1));
  }
  els.viewTabs.replaceChildren();
  list.items.forEach((v, i) => {
    const b = document.createElement("button");
    b.className = i === list.index ? "tab on" : "tab";
    b.textContent = v.name;
    b.role = "tab";
    b.addEventListener("click", () => {
      list.select(i);
      drawTabs();
      drawPart();
    });
    b.addEventListener("dblclick", () => {
      if (list.fixed(v)) return;
      const name = prompt(`${list.what} name`, v.name);
      if (!name || name === v.name) return;
      setSource(list.rename(source(), i, name));
      drawTabs();
      drawGutter(source());
      scheduleReload();
    });
    els.viewTabs.append(b);
  });
  const add = document.createElement("button");
  add.className = "tab add";
  add.textContent = "+";
  add.title = `add a ${list.what}`;
  add.addEventListener("click", () => {
    const name = prompt(
      `new ${list.what} name`,
      `${list.what}${list.items.length}`,
    );
    if (!name) return;
    setSource(list.add(source(), name));
    list.select(list.count(source()) - 1);
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
  if (part === "views" || part === "macros") drawTabs();
  drawPart();
}

// ---------------------------------------------------------------------------
// the other backend
//
// The card above is INTERPRETED. The same source also goes through
// `tutucard/wasm`, which compiles it to a `tutuca:component@0.8.0` core wasm
// module — in this page, with no server and no toolchain — and the panel shows
// what came out. Two answers to one card, side by side, so a difference between
// them is visible rather than theoretical.

/** The last successful compile, held for the download button. */
let lastBuild = null;

/** Which output pane is showing. Wax by default: it is what the generator SAID. */
let outTab = "wax";

function drawRefusals(refusals) {
  els.refusals.replaceChildren();
  for (const r of refusals) {
    const li = document.createElement("li");
    li.className = "issue warn";
    const code = document.createElement("span");
    code.className = "code";
    code.textContent = `${r.kind} ${r.name}`;
    const msg = document.createElement("span");
    msg.textContent = r.reason;
    li.append(code, msg);
    els.refusals.append(li);
  }
}

function drawCompiled() {
  els.compiled.textContent = lastBuild ? lastBuild[outTab] : "";
}

/**
 * Draw the compile panel from a build `reload` already did.
 *
 * It used to compile a SECOND time — once to mount the card, once to fill this
 * panel — because mounting went through an interpreter and the panel was the
 * only thing that wanted a module. Mounting is compiling now, so the panel
 * takes what came back rather than asking again.
 */
function showBuild(report) {
  if (!report || !report.ok) {
    // The panel says so on its own rather than blanking the preview beside it:
    // a card that does not compile may still be a card whose last render is
    // worth looking at.
    lastBuild = null;
    els.download.disabled = true;
    els.load.disabled = true;
    els.wasmSize.textContent = "";
    els.refusals.replaceChildren();
    els.compiled.textContent = report?.error ?? "did not compile";
    els.compiled.classList.add("bad");
    staleMount();
    return;
  }
  els.compiled.classList.remove("bad");
  lastBuild = report;
  els.wasmSize.textContent = `${(report.size / 1024).toFixed(1)} KB · ${report.fields.length} field${report.fields.length === 1 ? "" : "s"}`;
  els.download.disabled = false;
  els.load.disabled = false;
  drawRefusals(report.refusals);
  drawCompiled();
  staleMount();
}

// ---------------------------------------------------------------------------
// ...and the module RUNNING
//
// The download proves the bytes. This runs them. `card-wasm.js` instantiates
// the module through the host's own `abi.mjs` and installs it as
// `globalThis.__cardguest`; `mountCompiled` implements dyncomp's `&Guest` over
// those five calls, registers the manifest as an ordinary bundle and mounts an
// instance into the pane below (`tutucard/playground/cardguest.mbt`).
//
// Nothing on either side of that is card-specific once the module exists —
// `register_bundle` is the call the universal host makes over a dropped
// archive — which is the claim this button turns into something a reader can
// check by pressing it.

/** Whether a compiled card is mounted, so a later build can mark it behind. */
let mounted = false;

/**
 * The mounted card is a snapshot of the build it came from, and the editor has
 * moved on. Dimmed rather than torn down, for the reason the preview is dimmed
 * while a card does not parse: what is on screen is a real running module, it
 * is just not this source any more.
 */
function staleMount() {
  if (mounted) els.loaded.classList.add("stale");
}

/** The bundle's view findings — the only feedback a guest's views ever get. */
function drawLoadedIssues(lines) {
  els.loadedIssues.replaceChildren();
  for (const line of lines ?? []) {
    const li = document.createElement("li");
    li.className = "issue warn";
    li.textContent = line;
    els.loadedIssues.append(li);
  }
}

/** margaui for the mounted card, scoped to its own pane like the preview. */
function styleMounted() {
  let classes = [];
  try {
    classes = JSON.parse(globalThis.__tutucard.classesAt("loaded"));
  } catch {
    return;
  }
  if (classes.length) {
    els.loaded.dataset.theme = "dark";
    addClasses(classes, { scope: "#loaded", styleId: "loaded-margaui" });
  }
}

/** Instantiate the last successful build and mount it. */
async function loadAndMount() {
  if (!lastBuild) return;
  els.loadedNote.textContent = "instantiating…";
  els.loadedNote.className = "note";
  els.loadedIssues.replaceChildren();
  let report;
  try {
    // Imported lazily, with the packer beside it: a reader who never presses
    // this never fetches the guest bridge or the ABI it stands on.
    const { loadGuest, b64ToBytes } = await import("./card-wasm.js");
    // The manifest travels with the module it was compiled WITH. Its field list
    // is the order `get-field` answers in, so a manifest paired with any other
    // build would be a bundle whose halves disagree.
    // Keyed by "loaded", which is this pane's own mount point: the preview
    // above is a compiled card too now, and the two must not share a module.
    await loadGuest(b64ToBytes(lastBuild.wasm), lastBuild.descriptor, "loaded");
    report = JSON.parse(
      globalThis.__tutucard.mountCompiled(
        "loaded",
        JSON.stringify(lastBuild.manifest),
      ),
    );
  } catch (e) {
    // A throw is `abi.mjs` refusing the module — most often for a capability
    // its import section asks for and the empty grants list does not answer.
    report = { ok: false, error: String(e) };
  }
  if (!report.ok) {
    mounted = false;
    els.loaded.replaceChildren();
    els.loaded.classList.remove("stale");
    els.loadedNote.textContent = "refused";
    els.loadedNote.className = "note bad";
    drawLoadedIssues([report.error ?? "did not mount"]);
    return;
  }
  mounted = true;
  els.loaded.classList.remove("stale");
  els.loadedNote.textContent = `${report.module} · ${report.component}`;
  els.loadedNote.className = "note good";
  drawLoadedIssues(report.diagnostics);
  styleMounted();
}

els.load.addEventListener("click", loadAndMount);

for (const b of document.querySelectorAll("[data-out]")) {
  b.addEventListener("click", () => {
    outTab = b.dataset.out;
    for (const other of document.querySelectorAll("[data-out]")) {
      const on = other === b;
      other.classList.toggle("on", on);
      other.setAttribute("aria-selected", String(on));
    }
    drawCompiled();
  });
}

els.download.addEventListener("click", async () => {
  if (!lastBuild) return;
  // The packer is `card-wasm.js`'s, and the archive is the ordinary shape:
  // `tutuca.json` plus one core wasm, and no executable JavaScript in it.
  // Imported lazily so a reader who never downloads never fetches it.
  const { packBundle, b64ToBytes } = await import("./card-wasm.js");
  const blob = await packBundle(lastBuild, b64ToBytes(lastBuild.wasm));
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${lastBuild.component.toLowerCase()}.tutuca.tar.gz`;
  a.click();
  URL.revokeObjectURL(a.href);
});

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
  // `change` is here for the same reason as the other two, and it is not
  // redundant: a file input raises nothing else. The click that opens the
  // chooser redraws both panels before a file exists, so without this the
  // panes would sit on the state the card had before the pick.
  for (const name of ["click", "input", "change"]) {
    $("preview").addEventListener(
      name,
      () => setTimeout(() => {
        drawState();
        drawActivity();
      }, 0),
      true,
    );
  }
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
