// Playground driver (main thread): wires the editors to the compiler worker and
// mounts the linked module in an isolated iframe preview, with a state/activity
// inspector. The editors are shared CodeMirror instances (createEditor, bundled
// into ./editor.bundle.js); the worker RPC + iframe mounting live in
// ./runtime.js (both shared with the embeddable <mb-playground> element used by
// the landing site).
//
// Three tabs over the left pane:
//
//   Component  the .mbt the user writes
//   View       the .html its views live in
//   Generated  read-only: what `tutuca gen` makes of the View tab
//
// Editing the View tab regenerates the module (./viewgen-client.js, over the
// view generator compiled to JS) and the result is handed to the worker as
// EXTRA FILES OF THE USER'S PACKAGE. Same package means the component tab can
// name CounterMsg / counter_views with no import — that is what
// "auto-imported" amounts to here.
//
// A fourth tab, Inspect, holds the state snapshot and the activity log. They
// used to sit UNDER the preview, which cost the thing being looked at half its
// pane; as a tab of THIS pane they are beside the preview instead — visible at
// the same time, and free when not asked for. The right pane is now nothing
// but the preview, which grows again whenever this one is narrowed or
// collapsed (Ctrl/⌘+B).

import { errorDiagnostics, makeCompiler, mount, mountWasm, playgroundConfig } from "./runtime.js";
import { createEditor } from "./editor.bundle.js";
import { componentName, componentNames, generateViews } from "./viewgen-client.js";

const $ = (s) => document.querySelector(s);
// This shell ships inside the payload folder, so everything defaults to a
// sibling of THIS module rather than of the page — the folder can be served
// from anywhere. See playgroundConfig for the globalThis.MB_PLAYGROUND knobs.
const urls = playgroundConfig(new URL("./", import.meta.url));
const compiler = makeCompiler(urls.workerUrl, urls);

const editor = createEditor({ parent: $("#editor"), doc: window.STARTER || "", onRun: run });
const viewEditor = createEditor({
  parent: $("#view-editor"),
  doc: window.STARTER_VIEW || "",
  lang: "html",
  onRun: run,
  onChange: () => scheduleGenerate(),
});
const genEditor = createEditor({ parent: $("#gen-editor"), readOnly: true });
const genNote = $("#gen-note");
const status = $("#status");
const diags = $("#diagnostics");
const stateOut = $("#state");
const activity = $("#activity");
const preview = $("#preview");
const targetSel = $("#target");

// --- tabs ------------------------------------------------------------------
// The inspector is a tab of this pane too, so state and activity sit BESIDE the
// running component rather than under it — both readable at once, and the
// preview keeps its pane whole.
const TABS = [
  ["#tab-component", "#editor"],
  ["#tab-view", "#view-editor"],
  ["#tab-generated", "#gen-editor"],
  ["#tab-inspect", "#inspect"],
];
const inspectTab = $("#tab-inspect");
const inspectOpen = () => inspectTab.getAttribute("aria-selected") === "true";
function selectTab(btnSel) {
  for (const [b, panel] of TABS) {
    const on = b === btnSel;
    $(b).setAttribute("aria-selected", String(on));
    $(panel).hidden = !on;
  }
  // CodeMirror measures lazily; a pane revealed after layout needs a nudge.
  if (btnSel === "#tab-view") viewEditor.view.requestMeasure();
  if (btnSel === "#tab-generated") genEditor.view.requestMeasure();
  if (btnSel === "#tab-component") editor.view.requestMeasure();
  if (inspectOpen()) inspectTab.classList.remove("has-news");
}
for (const [b] of TABS) $(b).addEventListener("click", () => selectTab(b));

// --- code panel: collapse + resize ------------------------------------------
// Collapsing hands the code pane's width to the preview; the width itself is a
// CSS custom property the splitter drags. Both survive a reload, because the
// layout someone settles on is part of how they read the page.
const workbench = $("#workbench");
const LAYOUT_KEY = "mb-playground.layout";
const readLayout = () => {
  try { return JSON.parse(localStorage.getItem(LAYOUT_KEY)) || {}; } catch { return {}; }
};
const writeLayout = (patch) => {
  try { localStorage.setItem(LAYOUT_KEY, JSON.stringify({ ...readLayout(), ...patch })); } catch {}
};

// The editors are position:absolute inside a pane whose width just changed;
// CodeMirror only re-measures when asked.
function remeasureEditors() {
  for (const e of [editor, viewEditor, genEditor]) e.view.requestMeasure();
}

const codeCollapsed = () => workbench.classList.contains("code-collapsed");
function setCodeCollapsed(on, { remember = true } = {}) {
  workbench.classList.toggle("code-collapsed", on);
  $("#collapse-code").setAttribute("aria-expanded", String(!on));
  $("#expand-code").setAttribute("aria-expanded", String(!on));
  if (remember) writeLayout({ collapsed: on });
  if (!on) remeasureEditors();
}
$("#collapse-code").addEventListener("click", () => setCodeCollapsed(true));
$("#expand-code").addEventListener("click", () => {
  setCodeCollapsed(false);
  editor.view.focus();
});
// Ctrl/⌘+B toggles, the same key every editor uses for its sidebar. Neither
// CodeMirror keymap claims it, so it works with the cursor in the editor too.
addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "b") {
    e.preventDefault();
    setCodeCollapsed(!codeCollapsed());
  }
});

// Splitter: drag sets --code-w on main. Clamped so neither pane can be dragged
// out of existence — collapsing is the button's job, not an accident of aim.
// The floor is in px, not per cent: a percentage that leaves room for the tab
// strip on a wide monitor leaves none on a laptop.
const MIN_CODE_PX = 220;
const splitter = $("#splitter");
function setCodeWidth(px, { remember = true } = {}) {
  const total = workbench.clientWidth;
  const pct = (Math.min(total * 0.8, Math.max(MIN_CODE_PX, px)) / total) * 100;
  workbench.style.setProperty("--code-w", `${pct.toFixed(2)}%`);
  if (remember) writeLayout({ codeWidth: pct });
  remeasureEditors();
}
splitter.addEventListener("pointerdown", (e) => {
  if (codeCollapsed()) return;
  splitter.focus(); // preventDefault below would otherwise cost it the click focus
  splitter.setPointerCapture(e.pointerId);
  splitter.classList.add("dragging");
  const move = (ev) => setCodeWidth(ev.clientX - workbench.getBoundingClientRect().left, { remember: false });
  const up = () => {
    splitter.classList.remove("dragging");
    splitter.removeEventListener("pointermove", move);
    splitter.removeEventListener("pointerup", up);
    writeLayout({ codeWidth: parseFloat(workbench.style.getPropertyValue("--code-w")) });
  };
  splitter.addEventListener("pointermove", move);
  splitter.addEventListener("pointerup", up);
  e.preventDefault();
});
// Keyboard equivalent, so the divider is not mouse-only.
splitter.addEventListener("keydown", (e) => {
  const step = e.key === "ArrowLeft" ? -32 : e.key === "ArrowRight" ? 32 : 0;
  if (!step) return;
  e.preventDefault();
  setCodeWidth($(".pane.code").getBoundingClientRect().width + step);
});

(function restoreLayout() {
  const saved = readLayout();
  if (typeof saved.codeWidth === "number") {
    workbench.style.setProperty("--code-w", `${saved.codeWidth}%`);
  }
  if (saved.collapsed) setCodeCollapsed(true, { remember: false });
})();

// --- view -> generated module ----------------------------------------------
let generated = { module: "", ir: "" };

// Regenerate from the View tab. Returns true when the module is usable; a
// generation failure is reported like a compile error and leaves the previous
// module in place so a half-typed tag does not blank the Generated tab.
function generate() {
  const html = viewEditor.getValue().trim();
  if (!html) {
    generated = { module: "", ir: "" };
    genEditor.setValue("");
    genNote.textContent = "";
    return true;
  }
  const name = componentName(html);
  const r = generateViews(html, name);
  if (!r.ok) {
    genNote.textContent = "view error";
    diags.textContent = `view.html: ${r.error}`;
    return false;
  }
  generated = { module: r.module, ir: r.ir };
  genEditor.setValue(r.ir ? r.module + "\n" + r.ir : r.module);
  const declared = componentNames(html).join(", ");
  genNote.textContent = r.ir
    ? `${declared} — types + compiled tree`
    : `${declared} — types only (a macro blocks the compiled tree)`;
  return true;
}

// Debounced so typing a tag does not regenerate on every keystroke.
let genTimer = null;
function scheduleGenerate() {
  clearTimeout(genTimer);
  genTimer = setTimeout(() => {
    if (generate()) diags.textContent = "";
  }, 250);
}

// Which targets the assembled payload actually carries (assemble.mjs emits both
// unless it was run with JS_ONLY=1). Filled in at boot from the manifest so the
// toggle can't offer a backend the worker can't load.
let availableTargets = ["js"];
const currentTarget = () => targetSel.value;

// Which backend a fresh load compiles to. `?target=wasm-gc|js` wins, so a link
// can pin one (a bug report, a doc that needs the other backend); otherwise
// wasm-gc, which links ~0.26 MB against the js payload's ~1.1 MB and is what
// the landing page's embeds run. A payload without wasm-gc (JS_ONLY=1) or a
// `?target=` naming a backend it doesn't carry falls back to js rather than
// offering a toggle the worker can't honour.
function bootTarget() {
  const asked = new URLSearchParams(location.search).get("target");
  if (asked && availableTargets.includes(asked)) return asked;
  return availableTargets.includes("wasm-gc") ? "wasm-gc" : "js";
}

// Keep ?target= in step with the toggle, so the URL in the address bar is
// always the one that reproduces what is on screen.
function rememberTarget(target) {
  const url = new URL(location.href);
  url.searchParams.set("target", target);
  history.replaceState(null, "", url);
}

function setStatus(msg, cls) {
  status.textContent = msg;
  status.className = cls || "";
}

// --- preview: fresh realm per run, wired to the state/activity inspector ---
// The Activity panel is the transactor's observer stream, newest first: one
// line per handler invocation with its bucket, name, path and whether the leaf
// changed. It used to be a numbered list of state STRINGS — the records could
// not be serialized, because `before`/`after` are component instances and an
// instance had no JSON form.
function activityLine(e) {
  const args = (e.args || []).map((a) => JSON.stringify(a)).join(", ");
  const at = e.path ? ` at .${e.path}` : "";
  const changed = "after" in e ? "" : "  (no change)";
  const miss = e.matched === "none" ? "  (no handler)" : "";
  return `#${e.seq} ${e.kind} ${e.name}(${args})${at}${changed}${miss}`;
}

function inspectorOnState() {
  return (s, a) => {
    stateOut.textContent = tryPretty(s);
    // The inspector is behind a tab now: flag it when it changes out of sight.
    if (!inspectOpen()) inspectTab.classList.add("has-news");
    if (a == null) return;
    let entries = [];
    try { entries = JSON.parse(a); } catch { return; }
    activity.textContent = entries.slice().reverse().map(activityLine).join("\n");
  };
}

function mountPreview(jsText) {
  mount(preview, jsText, { onState: inspectorOnState() });
}

// wasm-gc: `result` is a wasm binary, not JS text — instantiate + drive from wasm.
async function mountPreviewWasm(wasmBytes) {
  await mountWasm(preview, wasmBytes, { onState: inspectorOnState() });
}

// The diagnostics panel lives in the code pane, so a failure while that pane is
// collapsed would be a red status line and nothing else. Bring it back — the
// reader has to see the message to act on it.
function revealDiagnostics() {
  if (codeCollapsed()) setCodeCollapsed(false);
}

function tryPretty(s) {
  try { return JSON.stringify(JSON.parse(s), null, 2); } catch { return s; }
}

// --- compile + run ---
let compiling = false;
// set once if a wasm-gc mount throws — usually an engine with no
// JS-String-Builtins, so don't try that backend again this session (see the
// fallback below). "Usually" is why the reason is kept and shown: a LinkError
// from a stale import object looks identical from here, and reporting it as an
// engine limitation is how one went unnoticed through a release.
let wasmFellBack = false;
let fellBackBecause = "";
async function run() {
  if (compiling) return;
  compiling = true;
  let fallback = false;
  // Loading the compiler/payload can fail on its own (a missing payload, a
  // compiler that doesn't pair with it); that is not the backend's fault, and
  // calling it "wasm instantiate failed" buries the message that explains it.
  let loaded = false;
  const target = currentTarget();
  setStatus(`compiling (${target})…`, "busy");
  diags.textContent = "";
  try {
    await compiler.init(target); // load this target's payload (once per target)
    loaded = true;
    // Always regenerate before compiling: the View tab is the source of truth
    // for the generated module, and a debounce may still be pending.
    if (!generate()) {
      setStatus("view error", "error");
      revealDiagnostics();
      return;
    }
    const r = await compiler.compile(
      editor.getValue(),
      generated.module,
      generated.ir,
      target,
    );
    const errs = errorDiagnostics(r.diagnostics);
    diags.textContent = (r.diagnostics || []).join("\n\n");
    editor.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
    if (!r.ok || errs.length) {
      // A build can fail with nothing errorDiagnostics() recognizes — a
      // non-exhaustive match arrives as "Error Warning (partial_match)",
      // which is exactly what a regenerated view produces when the component
      // has not caught up. Don't report that as "0 errors".
      setStatus(errs.length ? `compile errors (${errs.length})` : "compile failed", "error");
      revealDiagnostics();
      return;
    }
    let mountErr = null;
    try {
      if (target === "wasm-gc") {
        // linkCore returned a wasm binary; instantiate + drive the DOM from wasm.
        await mountPreviewWasm(r.result);
      } else {
        mountPreview(new TextDecoder().decode(r.result));
      }
    } catch (e) {
      mountErr = e;
    }
    // It compiled AND linked, so a throw from the mount alone is the engine's
    // fault rather than the reader's — most likely no JS-String-Builtins, which
    // the wasm payload needs. wasm-gc is the default now, so a browser without
    // them would otherwise fail on every load: drop to js once, say so, and
    // re-run. Same move the landing page's embeds make. Only the mount is
    // treated this way; a compile that throws is a real failure and reports.
    if (!mountErr) {
      setStatus(`ok — compiled + linked (${target}) in ${r.ms} ms`, "ok");
    } else if (target === "wasm-gc" && !wasmFellBack) {
      wasmFellBack = true;
      fellBackBecause = String(mountErr?.message || mountErr);
      targetSel.value = "js";
      rememberTarget("js");
      fallback = true;
    } else {
      throw mountErr;
    }
  } catch (e) {
    setStatus(
      !loaded ? "compiler failed to load" : target === "wasm-gc" ? "wasm instantiate failed" : "worker error",
      "error",
    );
    diags.textContent = String(e.stack || e.message || e);
    editor.setDiagnostics([]);
    revealDiagnostics();
  } finally {
    compiling = false;
  }
  if (fallback) {
    await run();
    setStatus(`${status.textContent} — wasm-gc mount failed, fell back to js`, "ok");
    diags.textContent = `wasm-gc mount failed, fell back to js:\n${fellBackBecause}`;
  }
}

// Ctrl/⌘+Enter (run) and Tab-indent are handled inside the editor's keymap.
$("#run").addEventListener("click", run);

// example picker — examples define only `build()`; the worker injects the
// target boot glue, so ONE example set drives both backends.
const examplesSel = $("#examples");
const exampleSet = () => window.EXAMPLES || {};
function fillExamples() {
  const set = exampleSet();
  examplesSel.innerHTML = "";
  for (const name of Object.keys(set)) {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    examplesSel.appendChild(opt);
  }
}
examplesSel.addEventListener("change", () => {
  const chosen = exampleSet()[examplesSel.value];
  // An example is either a plain source string, or { code, view } when it
  // carries a View tab of its own.
  if (typeof chosen === "string") {
    editor.setValue(chosen);
    viewEditor.setValue("");
  } else {
    editor.setValue(chosen.code);
    viewEditor.setValue(chosen.view || "");
  }
  run();
});

// target toggle — recompile the SAME source against the other backend (the
// worker swaps its payload on init and injects that target's boot glue).
targetSel.addEventListener("change", () => {
  rememberTarget(currentTarget());
  run();
});

// --- boot ---
(async () => {
  setStatus("loading compiler…", "busy");
  try {
    // The manifest lists the targets the payload actually carries; hide any
    // toggle option the build didn't assemble (wasm-gc needs a WASMGC=1 build).
    try {
      const manifest = await (await fetch(urls.manifestUrl)).json();
      availableTargets = Object.keys(manifest.targets || { js: 1 });
    } catch {}
    for (const opt of targetSel.options) {
      opt.disabled = !availableTargets.includes(opt.value);
    }
    targetSel.value = bootTarget();
    fillExamples();
    generate();
    const info = await compiler.init(currentTarget());
    const wasmNote = availableTargets.includes("wasm-gc")
      ? ""
      : " (wasm-gc: rebuild without JS_ONLY=1)";
    setStatus(`ready (compiler + ${info.std + info.lib} interfaces, ${info.cores} cores). Ctrl/⌘+Enter to run.${wasmNote}`, "ok");
    run();
  } catch (e) {
    setStatus("failed to load compiler", "error");
    diags.textContent = String(e.message || e);
  }
})();
