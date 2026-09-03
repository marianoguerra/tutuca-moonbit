// Regenerate `anode/sanitize/css/properties_gen.mbt` from the W3C's own
// machine-readable extracts of the CSS specifications.
//
// The CSS validator has to answer one question before any other: which
// properties can reach a URL. Getting it wrong in the permissive direction is
// an exfiltration channel, and the answer is spread across sixty specs and
// several layers of `<type>` indirection — `background` is a shorthand for
// `<bg-layer>#`, which contains `<bg-image>`, which is `<image> | none`, which
// is `<url> | <gradient>`, which is `<url()> | <src()>`. Nobody can hold that
// in their head, and the hand-written list this replaces
// (`tgc/policy/view_authority.mbt`) had seven misses, including the
// `background` shorthand itself.
//
// So the facts come from the specs and the POLICY stays in MoonBit. This script
// emits only what a specification states: the set of property names, which of
// them transitively reach a URL, a string or a colour, and the literal keywords
// each one's grammar admits. Which of those properties a level allows, and
// which count as overlay, is a judgement and lives in `properties.mbt` beside
// the argument for it — held against this file by a test.
//
// The source is `ed/css/` in w3c/webref, which is generated from the specs by
// reffy and is what the `@webref/css` npm package ships. `WEBREF_COMMIT` pins
// it: that repository is updated by a bot several times a day, so an unpinned
// fetch would mean the committed .mbt and this script silently stop
// corresponding.
//
// To pick up a spec change: bump WEBREF_COMMIT, re-run, and commit the pin
// together with the regenerated file. Read the diff — a name entering
// `url_properties` is a property the validator must stop admitting.
//
// Run:  node scripts/fetch-css-properties.mjs
//
// `--check` regenerates into memory and compares. It carries the same caveat as
// `fetch-sanitizer-defaults.mjs`: this script emits UNFORMATTED MoonBit and the
// committed file has been through `moon fmt`, so a byte difference is not proof
// the specs changed. The honest check is the `css-properties` task, which
// regenerates, formats, and then `git diff --exit-code`s.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// w3c/webref, pinned. 2026-08-14.
export const WEBREF_COMMIT = "7a9fc2cfa944cf4be3eb32f0511edb282cb71160";

// mdn/data, pinned. A SECOND source, for three productions and no others.
//
// css-color defines `<named-color>` and `<system-color>` as tables of prose
// rather than as a grammar, so webref's extract of them is the empty string —
// which would silently make every colour keyword unknown. mdn/data carries the
// same lists in machine-readable form. Reaching for it is narrower than it
// looks: `MDN_TYPES` names exactly what it may supply, and it is consulted only
// where webref has nothing, so a webref that starts publishing these wins.
export const MDN_COMMIT = "024ee9420264ff50a0475ce885d227c5d96ea50c";
const MDN_TYPES = ["named-color", "system-color", "deprecated-system-color"];

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "anode/sanitize/css/properties_gen.mbt");

const TREE =
  `https://api.github.com/repos/w3c/webref/git/trees/${WEBREF_COMMIT}?recursive=1`;
const RAW = (path) =>
  `https://raw.githubusercontent.com/w3c/webref/${WEBREF_COMMIT}/${path}`;
const MDN_SYNTAXES =
  `https://raw.githubusercontent.com/mdn/data/${MDN_COMMIT}/css/syntaxes.json`;

// The productions that put a fetchable URL in a value. `<url>` is the modern
// spelling and `<uri>` the CSS2 one; the rest are the image productions that
// take one without going through `<url>` — `image-set()` is the reason
// `background-image` is a sink even where a grammar names no `<url>` at all.
//
// A grammar that mentions any of these, at any depth, makes its property a
// sink. Both `<image()>` and `<image>` appear, and the `()` is stripped before
// the comparison, so one entry covers both spellings.
const URL_PRODUCTIONS = new Set([
  "url",
  "uri",
  "src",
  "image",
  "image-set",
  "cross-fade",
  "element",
]);

async function getJson(url) {
  const res = await fetch(url, {
    headers: { accept: "application/vnd.github+json" },
  });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

// A MoonBit string literal.
const lit = (s) => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;

// Every `<foo>` / `<foo()>` / `<'foo'>` reference in a value grammar. The
// quoted form is a reference to another PROPERTY's grammar, which is how
// shorthands are written, and it resolves in a different table from the rest.
function references(grammar) {
  const out = [];
  for (const m of grammar.matchAll(/<('?)([^<>]+?)\1>/g)) {
    const inner = m[2];
    out.push({ property: m[1] === "'", name: inner.replace(/\(\)$/, "") });
  }
  return out;
}

// The literal keywords in a grammar: bare identifiers that are not part of a
// `<...>` reference and not one of the grammar's own operators.
function keywords(grammar) {
  const stripped = grammar.replace(/<[^<>]*>/g, " ").replace(/\/\*[^]*?\*\//g, " ");
  const out = [];
  for (const m of stripped.matchAll(/[A-Za-z][A-Za-z0-9-]*/g)) {
    const word = m[0];
    // `n` and `of` come out of `<an+b>`-style prose; the CSS-wide keywords are
    // emitted once globally rather than onto every property.
    if (["inherit", "initial", "unset", "revert", "n", "of"].includes(word)) {
      continue;
    }
    out.push(word.toLowerCase());
  }
  return out;
}

// Collect every property and type definition across every spec, unioning the
// grammars rather than picking one. A property defined at several levels
// (`css-backgrounds` and `css-backgrounds-4`) gets both, and for a SINK
// question the union is the safe direction to be wrong in: a URL admitted by
// any level is a URL the browser will fetch.
function collect(specs) {
  const properties = new Map();
  const types = new Map();
  // A property with no grammar is still a property. SVG states `stop-color`
  // and `stop-opacity` in prose and css-fonts keeps `font-stretch` as a legacy
  // alias of `font-width` with no value line of its own, so all three extract
  // as the empty string — and dropping them would report a real property as a
  // typo. The NAME is recorded either way; only the grammar is absent, which
  // means the property contributes no keywords and reaches no URL, both of
  // which are the conservative answers.
  const push = (map, name, value) => {
    if (!map.has(name)) map.set(name, new Set());
    if (value) map.get(name).add(value);
  };
  const walkValues = (values) => {
    for (const v of values ?? []) {
      if (v.type === "type" && v.value) {
        push(types, v.name.replace(/^<|>$/g, ""), v.value);
      }
      walkValues(v.values);
    }
  };
  for (const spec of specs) {
    walkValues(spec.values);
    for (const p of spec.properties ?? []) {
      push(properties, p.name, p.value);
      walkValues(p.values);
    }
    // At-rule descriptors carry grammars too (`@font-face { src: }`), and they
    // define types the property grammars reach. Their descriptors are NOT
    // properties and are deliberately not collected as such.
    for (const at of spec.atrules ?? []) walkValues(at.values);
  }
  return { properties, types };
}

// Walk a property's grammar transitively, visiting each property/type once.
// Returns what the closure of that grammar can contain.
function facts(name, { properties, types }) {
  const seen = new Set();
  const stack = [{ property: true, name }];
  const found = { url: false, string: false, color: false };
  const kw = new Set();
  let colorReached = false;
  while (stack.length) {
    const node = stack.pop();
    const key = `${node.property ? "p" : "t"}:${node.name}`;
    if (seen.has(key)) continue;
    seen.add(key);
    if (!node.property) {
      if (URL_PRODUCTIONS.has(node.name)) found.url = true;
      if (node.name === "string") found.string = true;
      // `<color>` expands to 148 named colours plus the system colours. They
      // are emitted once, as `named_colors`, rather than copied onto every
      // property that takes a colour — so the subtree is recorded and not
      // descended into.
      if (node.name === "color") {
        found.color = true;
        colorReached = true;
        continue;
      }
    }
    const grammars =
      (node.property ? properties.get(node.name) : types.get(node.name)) ??
      new Set();
    for (const g of grammars) {
      // A grammar can also write a function call out literally.
      if (/\burl\(/.test(g) || /\bsrc\(/.test(g)) found.url = true;
      for (const word of keywords(g)) kw.add(word);
      for (const ref of references(g)) {
        if (!ref.property && URL_PRODUCTIONS.has(ref.name)) found.url = true;
        stack.push({ property: ref.property, name: ref.name });
      }
    }
  }
  // A colour-taking property's own keyword list would otherwise pick up the
  // function names inside `<color>`; it did not descend, so only its own words
  // are here.
  return { ...found, colorReached, keywords: [...kw].sort() };
}

function setLiteral(name, doc, values) {
  const lines = [];
  let line = "  ";
  for (const v of values.map(lit)) {
    if (line.length + v.length + 2 > 78) {
      lines.push(line.trimEnd());
      line = "  ";
    }
    line += v + ", ";
  }
  if (line.trim()) lines.push(line.trimEnd());
  return `///|
${doc}
pub let ${name} : @set.Set[String] = @set.Set::from_array([
${lines.join("\n")}
])
`;
}

export async function generate() {
  const tree = await getJson(TREE);
  const files = tree.tree
    .map((t) => t.path)
    .filter((p) => /^ed\/css\/[^/]+\.json$/.test(p))
    .sort();
  if (files.length < 50) {
    throw new Error(`only ${files.length} css extracts at this commit — wrong path?`);
  }
  const specs = [];
  for (const path of files) {
    const res = await fetch(RAW(path));
    if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
    specs.push(await res.json());
  }

  const tables = collect(specs);

  const mdn = await getJson(MDN_SYNTAXES);
  for (const type of MDN_TYPES) {
    const have = tables.types.get(type);
    if (have && [...have].some((g) => g.trim())) continue;
    const syntax = mdn[type]?.syntax;
    if (!syntax) throw new Error(`mdn/data has no syntax for <${type}>`);
    tables.types.set(type, new Set([syntax]));
  }

  const names = [...tables.properties.keys()].sort();
  if (!names.includes("background-image") || !names.includes("color")) {
    throw new Error("the extract has no background-image or color — wrong shape?");
  }

  const all = new Map(names.map((n) => [n, facts(n, tables)]));
  const url = names.filter((n) => all.get(n).url);
  const string_ = names.filter((n) => all.get(n).string);
  const color = names.filter((n) => all.get(n).color);
  const prose = names.filter((n) => tables.properties.get(n).size === 0);
  if (!url.includes("background") || !url.includes("background-image")) {
    throw new Error("background is not coming out as a URL sink — expansion broke");
  }

  // `<named-color>` is where the colour keywords live. Taking them from the
  // type rather than from a property keeps `transparent` and `currentcolor`,
  // which are spelled in `<color>` itself, in the same place.
  const colorWords = new Set();
  for (const type of [...MDN_TYPES, "color", "color-base"]) {
    for (const g of tables.types.get(type) ?? []) {
      for (const w of keywords(g)) colorWords.add(w);
    }
  }
  // The colour FUNCTIONS are validated by name in `values.mbt`, with an
  // argument grammar each; they must not leak into a bare-keyword allow-list.
  for (const g of tables.types.get("color-base") ?? []) {
    for (const ref of references(g)) colorWords.delete(ref.name);
  }
  if (colorWords.size < 140 || !colorWords.has("rebeccapurple")) {
    throw new Error(
      `only ${colorWords.size} colour keywords — <named-color> did not expand`,
    );
  }

  const keywordRows = [];
  for (const n of names) {
    const f = all.get(n);
    const words = f.keywords.filter((w) => !colorWords.has(w));
    if (words.length === 0) continue;
    keywordRows.push(`  (${lit(n)}, ${lit(words.join(" "))}),`);
  }

  const stamp = new Date().toISOString().slice(0, 10);
  return `// Generated by scripts/fetch-css-properties.mjs — DON'T EDIT IT.
//
// Source: w3c/webref, ed/css/*.json (${files.length} specification extracts), at
// commit ${WEBREF_COMMIT}.
// Also: mdn/data, css/syntaxes.json, at commit ${MDN_COMMIT}, for
// <${MDN_TYPES.join(">, <")}> — which css-color states as tables of
// prose, so webref extracts them as empty.
//
// ${names.length} properties, of which ${url.length} can reach a URL, ${string_.length} a string and
// ${color.length} a colour. Generated ${stamp}.
//
// These are FACTS FROM THE SPECIFICATIONS and nothing else. Which properties a
// level admits, and which of them can float content over the page around it,
// are judgements — they live in \`properties.mbt\`, and a test in
// \`properties_test.mbt\` holds them against this file.

${setLiteral(
  "css_properties",
  `/// Every property name any CSS specification defines.
///
/// Here so the hand-written level lists can be held against it: a name in a
/// level that is not in here is a typo or a property that was renamed out from
/// under us, and both fail the same test.`,
  names,
)}
${setLiteral(
  "url_properties",
  `/// Every property whose grammar can reach a URL, at any depth.
///
/// This is the load-bearing table. A property in here admits \`url()\` — or
/// \`image-set()\`, or \`src()\`, or one of the other image productions — and so
/// is an egress channel unless the \`UrlRule\` says otherwise. The expansion is
/// transitive because almost none of them say \`<url>\` directly:
/// \`background\` → \`<bg-layer>#\` → \`<bg-image>\` → \`<image>\` → \`<url>\`.
///
/// It is strictly larger than the hand-written list it replaces
/// (\`untrusted_sink_attr\` in \`tgc/policy/view_authority.mbt\`), and the
/// difference is the argument for generating it.`,
  url,
)}
${setLiteral(
  "string_properties",
  `/// Every property whose grammar can reach a \`<string>\`.
///
/// Strings are not dangerous in themselves — \`content\` is, but \`content\` is a
/// URL property too and refused for that reason. The table exists so a level
/// that admits no string token at all (\`Constant\`) can say which properties it
/// is therefore narrowing.`,
  string_,
)}
${setLiteral(
  "color_properties",
  `/// Every property whose grammar can reach a \`<color>\`.
///
/// A property in here accepts \`named_colors\`, a hex colour and the colour
/// functions, none of which are listed in \`property_keywords\` — the expansion
/// stops at \`<color>\` rather than copying 148 names onto every one of them.`,
  color,
)}
${setLiteral(
  "prose_properties",
  `/// Properties whose specification states their value in prose rather than in
/// a grammar, so nothing about their values could be extracted.
///
/// They are real properties and the level lists may name them. What they are
/// NOT is judged: they contribute no keywords, and they are absent from
/// \`url_properties\` because no grammar said they reach a URL rather than
/// because one said they do not. A level admitting one is trusting the name.`,
  prose,
)}
${setLiteral(
  "named_colors",
  `/// The colour keywords, including the system colours and \`transparent\`.
///
/// Emitted once and shared by every property in \`color_properties\`. The colour
/// FUNCTIONS are not in here: they are validated by name and argument shape in
/// \`values.mbt\`, because a function is a grammar and a keyword is not.`,
  [...colorWords].sort(),
)}
///|
/// The literal keywords each property's grammar admits, space-separated.
///
/// Transitively expanded, so \`display\` carries the keywords of
/// \`<display-outside>\`, \`<display-inside>\` and the rest rather than the type
/// names. Colour keywords are excluded — see \`named_colors\`. Grammars are
/// unioned across every level of every spec that defines a name, so a property
/// two specs happen to share (\`fill\` is SVG paint and a css-backgrounds
/// shorthand) carries both sets. That is over-permissive on IDENTS, which are
/// inert, and correctly conservative on \`url_properties\`, which are not.
///
/// This is an allow-list over IDENT tokens and nothing more. It encodes no
/// arity, no order and no combination rule, and it is not trying to:
/// \`text-align: block\` is refused by the BROWSER as invalid CSS, which costs
/// nothing and is not this validator's job. What the validator owes is that no
/// ident it admits can name a function, a URL, or a property outside the level.
///
/// \`properties.mbt\` turns it into a lookup.
let keyword_rows : Array[(String, String)] = [
${keywordRows.join("\n")}
]
`;
}

const out = await generate();
if (process.argv.includes("--check")) {
  const have = readFileSync(OUT, "utf8");
  if (have !== out) {
    console.error(
      `error: ${OUT} differs from freshly generated output.\n` +
        `NOTE: this compares unformatted output against a formatted file, so a\n` +
        `difference here is not proof the specs changed. Run the css-properties\n` +
        `task instead — it formats before comparing.`,
    );
    process.exit(1);
  }
  console.log("css properties are up to date");
} else {
  writeFileSync(OUT, out);
  console.log(`wrote ${OUT}`);
}
