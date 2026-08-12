// The card playground's shell.
//
// Everything here is presentation. The whole edit loop is one call —
// `__tutucard.load(source, name)` — and the rest of this file draws what it
// answers. There is no worker, no compiler client, no payload manifest and no
// toolchain pin, because there is nothing to compile: a card is parsed and
// mounted, and the runtime that does it is already on the page.

import { EXAMPLES } from "./examples.js";

const $ = (id) => document.getElementById(id);
const els = {
  source: $("source"),
  gutter: $("gutter"),
  issues: $("issues"),
  state: $("state"),
  activity: $("activity"),
  status: $("status"),
  example: $("example"),
};

/** Debounce, so a fast typist re-mounts on pauses rather than per keystroke. */
const DEBOUNCE_MS = 180;

/** Lines the last load complained about, for the gutter. */
let markedLines = new Set();

function componentName(source) {
  // The template's id names the component, when it has one. Otherwise the
  // interface name in the state block does, and failing both we pick
  // something — `load` only uses it as the fallback name.
  const tpl = source.match(/<template[^>]*\bid="([A-Z][\w:]*)"/);
  if (tpl) return tpl[1].split(":")[0];
  const iface = source.match(/\binterface\s+([a-z][\w-]*)/);
  if (iface) {
    return iface[1]
      .split("-")
      .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
      .join("");
  }
  return "Card";
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
  timer = setTimeout(reload, DEBOUNCE_MS);
}

function pickExample(name) {
  const ex = EXAMPLES.find((e) => e.name === name) ?? EXAMPLES[0];
  els.source.value = ex.source;
  reload();
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
