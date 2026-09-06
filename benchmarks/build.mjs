// Build the synthetic benchmark view: every view .html in the repo
// concatenated into one file, with every component name prefixed so nothing
// collides.
//
// Emits two checked-in artifacts:
//
//   benchmarks/all_views.html    — the concatenation, readable/debuggable
//   benchmarks/one_big_view.html — the same views inside one root
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

// The source with every `<!-- ... -->` span blanked out (same length, newlines
// kept). Matching tags against this and slicing the original keeps a `<template>`
// written inside a comment — playground/site/examples/composability.tutu has one
// in its header — from being mistaken for a real element.
function maskComments(source) {
  return source.replace(/<!--[\s\S]*?-->/g, c =>
    c.replace(/[^\n]/g, " "),
  );
}

// `<template id="Counter:row">` -> `<template id="<Prefix>Counter:row">`.
// A bare `<template>` names the file's single unnamed component, so it becomes
// `id="<Prefix>"` — the `Prefix:main` view. `macro:` ids would need their call
// sites rewritten too; no view file declares one, so it is an error here.
function prefixTemplates(source, prefix, path) {
  const masked = maskComments(source);
  let out = "";
  let at = 0;
  for (const m of masked.matchAll(/<template([^>]*)>/g)) {
    const [whole, attrs] = m;
    out = out + source.slice(at, m.index);
    at = m.index + whole.length;
    const id = attrs.match(/\bid\s*=\s*"([^"]*)"/);
    if (!id) {
      if (/\bid\s*=/.test(attrs)) {
        throw new Error(`${path}: unquoted template id, not supported`);
      }
      out = out + `<template id="${prefix}"${attrs}>`;
      continue;
    }
    if (id[1].startsWith("macro:")) {
      throw new Error(`${path}: macro templates would need call-site rewriting`);
    }
    const colon = id[1].indexOf(":");
    const renamed =
      colon < 0
        ? prefix + id[1]
        : prefix + id[1].slice(0, colon) + id[1].slice(colon);
    out = out + whole.replace(id[0], `id="${renamed}"`);
  }
  return out + source.slice(at);
}

// `<script type="tutuca/script">` -> `<script type="tutuca/script" for="<Prefix>">`.
//
// A block is written about ONE component, so the corpus — which concatenates
// every view file in the repo — cannot hold two unqualified ones. A bare
// `<template>` becomes `id="<Prefix>"` above, so the file's single unnamed
// component is `<Prefix>`, and that is what its block is about. A block that
// already names its component is left alone: the name it carries is one
// `prefixTemplates` has already rewritten.
function prefixScripts(source, prefix) {
  return source.replace(
    /<script type="tutuca\/script"(\s*)>/g,
    `<script type="tutuca/script" for="${prefix}">`,
  );
}

// A view file's `tutuca/spec` and `tutuca/init` blocks, removed. See the
// call site for why the concatenated corpus cannot keep them.
function stripStateBlocks(source) {
  return source.replace(
    /<script type="tutuca\/(?:spec|state|init)">[\s\S]*?<\/script>\n?/g,
    "",
  );
}

// Each top-level `<template>`'s inner source, which is what the one-big-view
// corpus concatenates. No view file nests templates, so the first `</template>`
// after an opening tag closes it.
function templateBodies(source) {
  const masked = maskComments(source);
  const bodies = [];
  for (const m of masked.matchAll(/<template[^>]*>/g)) {
    const from = m.index + m[0].length;
    const to = masked.indexOf("</template", from);
    bodies.push(
      source
        .slice(from, to < 0 ? source.length : to)
        .replace(/^\n/, "")
        .trimEnd(),
    );
  }
  return bodies;
}

// Corpus 1: many views. Every file's templates side by side, ids prefixed.
const manyParts = [
  "<!-- GENERATED by benchmarks/build.mjs — do not edit. -->",
  "<!-- Every view .html in the repo, component names prefixed per file. -->",
];
// Corpus 2: one view. Every view's BODY inside a single <template>, so the same
// node count arrives as one enormous tree instead of 108 small ones. Only the
// body is embedded, so the bench can wrap it once or N times over (the scaling
// probe in scaling_bench_test.mbt).
const bodyParts = [
  "  <!-- GENERATED by benchmarks/build.mjs — do not edit. -->",
  "  <!-- Every view body in the repo, concatenated into one view. -->",
];
let bodyCount = 0;
for (const [path, prefix] of VIEWS) {
  // Stripped BEFORE anything scans for tags. A schema block is WIT, not
  // markup, and its prose may say `<template>` — as filter_paginate's does,
  // explaining why its strategies have none — which the tag scan below would
  // otherwise take for an opening tag and slice a "body" from.
  const source = stripStateBlocks(readFileSync(join(root, path), "utf8"));
  manyParts.push(`<!-- ${path} (${prefix}) -->`);
  manyParts.push(prefixScripts(prefixTemplates(source, prefix, path), prefix).trimEnd());
  for (const body of templateBodies(source)) {
    bodyCount = bodyCount + 1;
    bodyParts.push(`  <!-- ${path} -->`);
    bodyParts.push(body);
  }
}

const GIANT_OPEN = '<template id="GiantView">';
const GIANT_CLOSE = "</template>";
const many = manyParts.join("\n") + "\n";
const body = bodyParts.join("\n");
const one = `${GIANT_OPEN}\n${body}\n${GIANT_CLOSE}\n`;
writeFileSync(join(root, "benchmarks/all_views.html"), many);
writeFileSync(join(root, "benchmarks/one_big_view.html"), one);

// The MoonBit twin of both. `#|` is a raw multi-line string: no interpolation,
// so the `{...}` and `\` a view body is full of need no escaping.
function lit(text) {
  return text
    .split("\n")
    .map(l => `  #|${l}`)
    .join("\n");
}
const manyText = many.replace(/\n$/, "");
const mbt = `// GENERATED by benchmarks/build.mjs from benchmarks/all_views.html and
// benchmarks/one_big_view.html — do not edit; regenerate with
// \`cmd/dev -- bench-views\`.

///|
/// Every view .html in the repo concatenated into one view FILE, component
/// names prefixed per source file so nothing collides: ${manyText.split("\n").length} lines,
/// ${manyText.length} chars, ${(many.match(/<template/g) ?? []).length} views.
pub let all_views : String =
${lit(manyText)}

///|
/// The body of benchmarks/one_big_view.html: every view body above, ${body.split("\n").length} lines
/// and ${body.length} chars of them, with no \`<template>\` wrapper. Wrapping it once
/// gives the same nodes as ONE enormous view instead of 108 small ones — see
/// \`giant_view\` — and wrapping it N times over scales a single view's size.
pub let one_big_view_body : String =
${lit(body)}
`;
writeFileSync(join(root, "benchmarks/corpus_gen.mbt"), mbt);

console.log(
  `all_views.html:    ${VIEWS.length} files, ` +
    `${(many.match(/<template/g) ?? []).length} views, ` +
    `${manyText.split("\n").length} lines, ${manyText.length} chars\n` +
    `one_big_view.html: ${bodyCount} bodies in 1 view, ` +
    `${one.split("\n").length - 1} lines, ${one.length - 1} chars`,
);
