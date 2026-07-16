// Playground driver (main thread): wires the editor to the compiler worker and
// mounts the linked module in an isolated iframe preview, with a state/activity
// inspector. The editor is a shared CodeMirror instance (createEditor, bundled
// into ./editor.bundle.js); the worker RPC + iframe mounting live in
// ./runtime.js (both shared with the embeddable <mb-playground> element used by
// the landing site).

import { errorDiagnostics, makeCompiler, mount } from "./runtime.js";
import { createEditor } from "./editor.bundle.js";

const $ = (s) => document.querySelector(s);
const compiler = makeCompiler("./compiler.worker.js");

const editor = createEditor({ parent: $("#editor"), doc: window.STARTER || "", onRun: run });
const status = $("#status");
const diags = $("#diagnostics");
const stateOut = $("#state");
const activity = $("#activity");
const preview = $("#preview");

function setStatus(msg, cls) {
  status.textContent = msg;
  status.className = cls || "";
}

// --- preview: fresh realm per run, wired to the state/activity inspector ---
function mountPreview(jsText) {
  const activityLog = [];
  mount(preview, jsText, {
    onState: (s) => {
      stateOut.textContent = tryPretty(s);
      activityLog.push(s);
      activity.textContent = activityLog.map((v, i) => `${i}: ${v}`).join("\n");
    },
  });
}

function tryPretty(s) {
  try { return JSON.stringify(JSON.parse(s), null, 2); } catch { return s; }
}

// --- compile + run ---
let compiling = false;
async function run() {
  if (compiling) return;
  compiling = true;
  setStatus("compiling…", "busy");
  diags.textContent = "";
  try {
    const r = await compiler.compile(editor.getValue());
    const errs = errorDiagnostics(r.diagnostics);
    diags.textContent = (r.diagnostics || []).join("\n\n");
    editor.setDiagnostics(r.diagnostics); // inline underlines mirror the panel
    if (!r.ok || errs.length) {
      setStatus(`compile errors (${errs.length})`, "error");
      return;
    }
    const js = new TextDecoder().decode(r.result);
    mountPreview(js);
    setStatus(`ok — compiled + linked in ${r.ms} ms`, "ok");
  } catch (e) {
    setStatus("worker error", "error");
    diags.textContent = String(e.message || e);
    editor.setDiagnostics([]);
  } finally {
    compiling = false;
  }
}

// Ctrl/⌘+Enter (run) and Tab-indent are handled inside the editor's keymap.
$("#run").addEventListener("click", run);

// example picker
const examplesSel = $("#examples");
const EXAMPLES = window.EXAMPLES || {};
for (const name of Object.keys(EXAMPLES)) {
  const opt = document.createElement("option");
  opt.value = name;
  opt.textContent = name;
  examplesSel.appendChild(opt);
}
examplesSel.addEventListener("change", () => {
  editor.setValue(EXAMPLES[examplesSel.value]);
  run();
});

// --- boot ---
(async () => {
  setStatus("loading compiler…", "busy");
  try {
    const info = await compiler.init("js");
    setStatus(`ready (compiler + ${info.std + info.lib} interfaces, ${info.cores} cores). Ctrl/⌘+Enter to run.`, "ok");
    run();
  } catch (e) {
    setStatus("failed to load compiler", "error");
    diags.textContent = String(e.message || e);
  }
})();
