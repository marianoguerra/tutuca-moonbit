// The card playground's shell.
//
// Everything here is presentation. The whole edit loop is one call —
// `__tutucard.load(source, name)` — and the rest of this file draws what it
// answers. There is no worker, no compiler client, no payload manifest and no
// toolchain pin, because there is nothing to compile: a card is parsed and
// mounted, and the runtime that does it is already on the page.

import { EXAMPLES } from "./examples.js";
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
  partEmpty: $("part-empty"),
  viewTabs: $("view-tabs"),
};

/**
 * Which pane is showing, and which part of the card it is showing.
 *
 * The RAW textarea holds the card; the structured panes are projections of the
 * same string. So there is one source of truth and no diffing: a structured
 * edit splices into `els.source.value` and everything redraws from there.
 */
const ui = { mode: "raw", part: "state", view: 0 };

/** Debounce, so a fast typist re-mounts on pauses rather than per keystroke. */
const DEBOUNCE_MS = 180;

/** Lines the last load complained about, for the gutter. */
let markedLines = new Set();

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

function drawGutter(source) {
  const lines = source.split("\n").length;
  const out = [];
  for (let i = 1; i <= lines; i++) {
    out.push(markedLines.has(i) ? `${i} ●` : `${i}`);
  }
  els.gutter.textContent = out.join("\n");
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
    where.addEventListener("click", () => {
      els.source.focus();
      els.source.setSelectionRange(issue.start, issue.end);
    });
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
  const source = els.source.value;
  const report = JSON.parse(
    globalThis.__tutucard.load(source, componentName(source)),
  );
  if (!report.ok) {
    // Nothing to mount: the file does not split, or the script does not parse.
    // The last render STAYS, dimmed, rather than blanking — a syntax error is
    // the ordinary state of a half-typed line, and a preview that goes empty
    // between two keystrokes is worse than one that is visibly behind. The
    // class is what says it is behind; the app itself is already torn down.
    markedLines = new Set([report.line]);
    els.status.textContent = "cannot load";
    els.status.className = "status bad";
    $("preview").classList.add("stale");
    drawIssues([
      {
        line: report.line,
        code: "SYNTAX",
        // The loader's message names its own line, because it is also what a
        // CLI would print. The gutter button says that here, so drop it.
        message: report.error.replace(/^line \d+: /, ""),
        start: report.start,
        end: report.end,
      },
    ]);
  } else {
    $("preview").classList.remove("stale");
    markedLines = new Set(report.issues.map((i) => i.line));
    const n = report.issues.length;
    els.status.textContent =
      n === 0 ? `${report.component} · ok` : `${report.component} · ${n} issue${n === 1 ? "" : "s"}`;
    els.status.className = n === 0 ? "status good" : "status warn";
    drawIssues(report.issues);
  }
  drawGutter(source);
  drawState();
  drawActivity();
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
  const p = parts(els.source.value);
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
    els.part.hidden = true;
    els.partEmpty.hidden = false;
    els.partEmpty.textContent = MISSING[ui.part];
    return;
  }
  els.partEmpty.hidden = true;
  els.part.hidden = false;
  // Only when it CHANGED: assigning `value` moves the caret to the end, and
  // this runs on the same debounce as the reload — so a typist would be
  // fighting it. A raw edit, another tab or a new example changes the region
  // out from under the pane; an edit made HERE does not redraw the pane it
  // came from.
  if (region.text !== paneEcho) {
    els.part.value = dedented(region.text);
    paneEcho = region.text;
  }
}

/** The view tabs, `main` first. */
function drawTabs() {
  const p = parts(els.source.value);
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
      els.source.value = renameView(els.source.value, p, i, name);
      drawTabs();
      drawGutter(els.source.value);
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
    els.source.value = addView(els.source.value, name);
    ui.view = parts(els.source.value).views.length - 1;
    drawTabs();
    drawPart();
    drawGutter(els.source.value);
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
  } else {
    drawGutter(els.source.value);
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
  const text = reindented(region.text, els.part.value);
  paneEcho = text;
  els.source.value = splice(els.source.value, region, text);
  scheduleReload();
}

function pickExample(name) {
  const ex = EXAMPLES.find((e) => e.name === name) ?? EXAMPLES[0];
  els.source.value = ex.source;
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
