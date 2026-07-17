// Playground driver (main thread): wires the editor to the compiler worker and
// mounts the linked module in an isolated iframe preview, with a state/activity
// inspector. The editor is a shared CodeMirror instance (createEditor, bundled
// into ./editor.bundle.js); the worker RPC + iframe mounting live in
// ./runtime.js (both shared with the embeddable <mb-playground> element used by
// the landing site).

import { errorDiagnostics, makeCompiler, mount, mountWasm } from "./runtime.js";
import { createEditor } from "./editor.bundle.js";

const $ = (s) => document.querySelector(s);
const compiler = makeCompiler("./compiler.worker.js");

const editor = createEditor({ parent: $("#editor"), doc: window.STARTER || "", onRun: run });
const status = $("#status");
const diags = $("#diagnostics");
const stateOut = $("#state");
const activity = $("#activity");
const preview = $("#preview");
const targetSel = $("#target");

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
    const r = await compiler.compile(editor.getValue());
    const errs = errorDiagnostics(r.diagnostics);
    diags.textContent = (r.diagnostics || []).join("\n\n");
    editor.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
    if (!r.ok || errs.length) {
      setStatus(`compile errors (${errs.length})`, "error");
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
  editor.setValue(exampleSet()[examplesSel.value]);
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
    const info = await compiler.init(currentTarget());
    const wasmNote = availableTargets.includes("wasm-gc") ? "" : " (wasm-gc: rebuild with WASMGC=1)";
    setStatus(`ready (compiler + ${info.std + info.lib} interfaces, ${info.cores} cores). Ctrl/⌘+Enter to run.${wasmNote}`, "ok");
    run();
  } catch (e) {
    setStatus("failed to load compiler", "error");
    diags.textContent = String(e.message || e);
  }
})();
