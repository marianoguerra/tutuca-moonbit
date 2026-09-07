// Build the synthetic benchmark view: every view .tutu in the repo
// concatenated into one file, with every component name prefixed so nothing
// collides.
//
// Emits two checked-in artifacts:
//
//   benchmarks/all_views.tutu    — the concatenation, readable/debuggable
//   benchmarks/one_big_view.tutu — the same views inside one root
//   benchmarks/corpus_gen.mbt    — both as MoonBit strings, so the bench runs
//                                  on every backend (wasm-gc has no filesystem)
//
// Run through the task runner so the .mbt gets formatted:
//   moon run --target native cmd/dev -- bench-views
//
// The view list mirrors dev/tasks.mbt's gen_views_commands() plus the
// playground site examples (which `check-examples` generates in the browser).

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const root = join(dirname(new URL(import.meta.url).pathname), "..");

// (path relative to the repo root, component-name prefix)
const VIEWS = [
  ["demo/counterlib/counter.tutu", "DemoCounter"],
  ["storybook/examples/basics.tutu", "SbBasics"],
  ["storybook/examples/collections.tutu", "SbCollections"],
  ["storybook/examples/communication.tutu", "SbCommunication"],
  ["storybook/examples/composability.tutu", "SbComposability"],
  ["storybook/examples/conditionals.tutu", "SbConditionals"],
  ["storybook/examples/counter.tutu", "SbCounter"],
  ["storybook/examples/custom_collection.tutu", "SbCustomCollection"],
  ["storybook/examples/dnd.tutu", "SbDnd"],
  ["storybook/examples/dynamic.tutu", "SbDynamic"],
  ["storybook/examples/dynamic_selected_edit.tutu", "SbDynamicSelectedEdit"],
  ["storybook/examples/file_picker.tutu", "SbFilePicker"],
  ["storybook/examples/filter_paginate.tutu", "SbFilterPaginate"],
  ["storybook/examples/graphics.tutu", "SbGraphics"],
  ["storybook/examples/json.tutu", "SbJson"],
  ["storybook/examples/list_iteration.tutu", "SbListIteration"],
  ["storybook/examples/nested_state.tutu", "SbNestedState"],
  ["storybook/examples/personal_site.tutu", "SbPersonalSite"],
  ["storybook/examples/pseudo_x.tutu", "SbPseudoX"],
  ["storybook/examples/render_child.tutu", "SbRenderChild"],
  ["storybook/examples/rendering.tutu", "SbRendering"],
  ["storybook/examples/request.tutu", "SbRequest"],
  ["storybook/examples/state_and_updates.tutu", "SbStateAndUpdates"],
  ["storybook/examples/styles.tutu", "SbStyles"],
  ["storybook/examples/todo.tutu", "SbTodo"],
  ["storybook/examples/web_component.tutu", "SbWebComponent"],
  ["playground/site/examples/composability.tutu", "SiteComposability"],
  ["playground/site/examples/counter.tutu", "SiteCounter"],
  ["playground/site/examples/dnd.tutu", "SiteDnd"],
  ["playground/site/examples/filter_paginate.tutu", "SiteFilterPaginate"],
  ["playground/site/examples/json.tutu", "SiteJson"],
  ["playground/site/examples/personal_site.tutu", "SitePersonalSite"],
  ["playground/site/examples/text_input.tutu", "SiteTextInput"],
  ["playground/site/examples/todo.tutu", "SiteTodo"],
  ["playground/site/examples/toggle.tutu", "SiteToggle"],
  ["playground/site/examples/tree.tutu", "SiteTree"],
];

// Every NAME a `.tutu` file declares at the top of a section: a component, a
// struct, an enum, a protocol. The corpus concatenates every view file in the
// repo into one, so each file's names are prefixed to keep them apart — and a
// name is only ever declared at one indent, which is what makes this a line
// scan rather than a parse.
function declaredNames(source) {
  const names = new Set();
  for (const line of source.split("\n")) {
    let m = line.match(/^  ([A-Z][A-Za-z0-9_]*)\s*(?:~root:|:)?\s*$/);
    if (m) names.add(m[1]);
    m = line.match(/^  (?:struct|enum|protocol)\s+([A-Z][A-Za-z0-9_]*)/);
    if (m) names.add(m[1]);
  }
  return names;
}

// The file with every name it declares prefixed, everywhere it appears: the
// section headers, `Instance.of(X)`, `List.of(X)`, `implements X`, a
// constructor call. Word-boundary replacement, because a `.tutu` name is a
// word and nothing else in the file spells one the same way.
function prefixNames(source, prefix) {
  let out = source;
  for (const name of declaredNames(source)) {
    out = out.replace(new RegExp(`\\b${name}\\b`, "g"), prefix + name);
  }
  return out;
}

// One section's body, by name. A section is a line at column 0 ending in `:`
// and everything indented under it.
function section(source, name) {
  const lines = source.split("\n");
  const at = lines.findIndex(l => l === name + ":");
  if (at < 0) return [];
  const body = [];
  for (let i = at + 1; i < lines.length; i = i + 1) {
    const l = lines[i];
    if (l !== "" && !l.startsWith(" ")) break;
    body.push(l);
  }
  while (body.length > 0 && body[body.length - 1].trim() === "") body.pop();
  return body;
}

// Corpus 1: many views. Every file's templates side by side, ids prefixed.
// Corpus 1: many views. Every file's three sections merged into one `.tutu`,
// with each file's own names prefixed so nothing collides.
const specParts = [];
const logicParts = [];
const viewParts = [];
// Corpus 2: one view. Every component's view body under a single component, so
// the same node count arrives as one enormous tree instead of 108 small ones.
// Only the bodies are embedded, so the bench can wrap them once or N times over
// (the scaling probe in scaling_bench_test.mbt).
const bodyParts = [];
let bodyCount = 0;
for (const [path, prefix] of VIEWS) {
  const source = prefixNames(readFileSync(join(root, path), "utf8"), prefix);
  const spec = section(source, "spec");
  const logic = section(source, "logic");
  const view = section(source, "view");
  if (spec.length > 0) {
    specParts.push(`  // ${path}`);
    specParts.push(...spec);
  }
  if (logic.length > 0) {
    logicParts.push(`  // ${path}`);
    logicParts.push(...logic);
  }
  if (view.length > 0) {
    viewParts.push(`  // ${path}`);
    viewParts.push(...view);
  }
  // A view body is what sits UNDER a component's name in the view section: two
  // levels of indent, re-indented to sit under one component of its own.
  for (let i = 0; i < view.length; i = i + 1) {
    // A component's name, and not a `style()` block at the top of `view:`.
    // Both sit at two spaces and both start with a letter -- the old notation
    // wrote `@style{...}`, whose `@` kept it out of this test by accident. A
    // style block's body is CSS, so harvesting it as a view body writes
    // declarations where markup belongs and the corpus stops parsing.
    if (!/^  [A-Za-z]/.test(view[i])) continue;
    if (/^  style\s*\(/.test(view[i])) continue;
    const body = [];
    for (let j = i + 1; j < view.length && (view[j] === "" || view[j].startsWith("    ")); j = j + 1) {
      body.push(view[j]);
    }
    while (body.length > 0 && body[body.length - 1].trim() === "") body.pop();
    if (body.length > 0) {
      bodyCount = bodyCount + 1;
      bodyParts.push(...body);
    }
  }
}

const HEAD = "// GENERATED by benchmarks/build.mjs — do not edit.\n" +
  "// Every view .tutu in the repo, component names prefixed per file.\n";
const many = HEAD +
  (specParts.length > 0 ? "spec:\n" + specParts.join("\n") + "\n\n" : "") +
  (logicParts.length > 0 ? "logic:\n" + logicParts.join("\n") + "\n\n" : "") +
  (viewParts.length > 0 ? "view:\n" + viewParts.join("\n") + "\n" : "");
const body = bodyParts.join("\n");
const one = "// GENERATED by benchmarks/build.mjs — do not edit.\n" +
  "// Every view body in the repo, concatenated into one view.\n" +
  "view:\n  GiantView:\n" + body + "\n";
writeFileSync(join(root, "benchmarks/all_views.tutu"), many);
writeFileSync(join(root, "benchmarks/one_big_view.tutu"), one);

// The MoonBit twin of both. `#|` is a raw multi-line string: no interpolation,
// so the `{...}` and `\` a view body is full of need no escaping.
function lit(text) {
  return text
    .split("\n")
    .map(l => `  #|${l}`)
    .join("\n");
}
const manyText = many.replace(/\n$/, "");
const mbt = `// GENERATED by benchmarks/build.mjs from benchmarks/all_views.tutu and
// benchmarks/one_big_view.tutu — do not edit; regenerate with
// \`cmd/dev -- bench-views\`.

///|
/// Every view .tutu in the repo concatenated into one view FILE, component
/// names prefixed per source file so nothing collides: ${manyText.split("\n").length} lines,
/// ${manyText.length} chars, ${bodyCount} views.
pub let all_views : String =
${lit(manyText)}

///|
/// The body of benchmarks/one_big_view.tutu: every view body above, ${body.split("\n").length} lines
/// and ${body.length} chars of them, with no component around them. Wrapping it once
/// gives the same nodes as ONE enormous view instead of 108 small ones — see
/// \`giant_view\` — and wrapping it N times over scales a single view's size.
pub let one_big_view_body : String =
${lit(body)}
`;
writeFileSync(join(root, "benchmarks/corpus_gen.mbt"), mbt);

console.log(
  `all_views.tutu:    ${VIEWS.length} files, ` +
    `${bodyCount} views, ` +
    `${manyText.split("\n").length} lines, ${manyText.length} chars\n` +
    `one_big_view.tutu: ${bodyCount} bodies in 1 view, ` +
    `${one.split("\n").length - 1} lines, ${one.length - 1} chars`,
);
