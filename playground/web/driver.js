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
//   Generated  read-only: what `tutuca gen-views` makes of the View tab
//
// Editing the View tab regenerates the module (./viewgen-client.js, over the
// view generator compiled to JS) and the result is handed to the worker as
// EXTRA FILES OF THE USER'S PACKAGE. Same package means the component tab can
// name CounterMsg / counter_views with no import — that is what
// "auto-imported" amounts to here.

import { errorDiagnostics, makeCompiler, mount, mountWasm } from "./runtime.js";
import { createEditor } from "./editor.bundle.js";
import { componentName, componentNames, generateViews } from "./viewgen-client.js";

const $ = (s) => document.querySelector(s);
const compiler = makeCompiler("./compiler.worker.js");

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
const TABS = [
  ["#tab-component", "#editor"],
  ["#tab-view", "#view-editor"],
  ["#tab-generated", "#gen-editor"],
];
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
}
for (const [b] of TABS) $(b).addEventListener("click", () => selectTab(b));

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

// Which targets the assembled payload actually carries (the wasm-gc option is
// only real when the site was built with WASMGC=1). Filled in at boot from the
// manifest so the toggle can't offer a backend the worker can't load.
let availableTargets = ["js"];
const currentTarget = () => targetSel.value;

function setStatus(msg, cls) {
  status.textContent = msg;
  status.className = cls || "";
}

// --- preview: fresh realm per run, wired to the state/activity inspector ---
function inspectorOnState() {
  const activityLog = [];
  return (s) => {
    stateOut.textContent = tryPretty(s);
    activityLog.push(s);
    activity.textContent = activityLog.map((v, i) => `${i}: ${v}`).join("\n");
  };
}

function mountPreview(jsText) {
  mount(preview, jsText, { onState: inspectorOnState() });
}

// wasm-gc: `result` is a wasm binary, not JS text — instantiate + drive from wasm.
async function mountPreviewWasm(wasmBytes) {
  await mountWasm(preview, wasmBytes, { onState: inspectorOnState() });
}

function tryPretty(s) {
  try { return JSON.stringify(JSON.parse(s), null, 2); } catch { return s; }
}

// --- compile + run ---
let compiling = false;
async function run() {
  if (compiling) return;
  compiling = true;
  const target = currentTarget();
  setStatus(`compiling (${target})…`, "busy");
  diags.textContent = "";
  try {
    await compiler.init(target); // switch the worker's payload if the target changed
    // Always regenerate before compiling: the View tab is the source of truth
    // for the generated module, and a debounce may still be pending.
    if (!generate()) {
      setStatus("view error", "error");
      return;
    }
    const r = await compiler.compile(
      editor.getValue(),
      generated.module,
      generated.ir,
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
      return;
    }
    if (target === "wasm-gc") {
      // linkCore returned a wasm binary; instantiate + drive the DOM from wasm.
      // A string-ABI mismatch in the vendored in-browser linker currently makes
      // this throw a WebAssembly.CompileError — surfaced in the diagnostics pane.
      await mountPreviewWasm(r.result);
    } else {
      mountPreview(new TextDecoder().decode(r.result));
    }
    setStatus(`ok — compiled + linked (${target}) in ${r.ms} ms`, "ok");
  } catch (e) {
    setStatus(target === "wasm-gc" ? "wasm instantiate failed" : "worker error", "error");
    diags.textContent = String(e.stack || e.message || e);
    editor.setDiagnostics([]);
  } finally {
    compiling = false;
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
targetSel.addEventListener("change", run);

// --- boot ---
(async () => {
  setStatus("loading compiler…", "busy");
  try {
    // The manifest lists the targets the payload actually carries; hide any
    // toggle option the build didn't assemble (wasm-gc needs a WASMGC=1 build).
    try {
      const manifest = await (await fetch("./manifest.json")).json();
      availableTargets = Object.keys(manifest.targets || { js: 1 });
    } catch {}
    for (const opt of targetSel.options) {
      opt.disabled = !availableTargets.includes(opt.value);
    }
    if (!availableTargets.includes(targetSel.value)) targetSel.value = "js";
    fillExamples();
    generate();
    const info = await compiler.init(currentTarget());
    const wasmNote = availableTargets.includes("wasm-gc") ? "" : " (wasm-gc: rebuild with WASMGC=1)";
    setStatus(`ready (compiler + ${info.std + info.lib} interfaces, ${info.cores} cores). Ctrl/⌘+Enter to run.${wasmNote}`, "ok");
    run();
  } catch (e) {
    setStatus("failed to load compiler", "error");
    diags.textContent = String(e.message || e);
  }
})();
