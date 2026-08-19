// Regenerate `render/dom_props_gen.mbt` from the browser specifications' own
// machine-extracted WebIDL.
//
// The table answers two questions about an `e.<path>` — does this interface
// have this property, and what is its type — and it is the type oracle for
// layer 1 and the lint source for layer 2 (`totuka-v2.md` section 7).
//
// It comes from the SPECIFICATIONS rather than from a summary of them, for the
// reason `AGENTS.md` states outright: the first hand-read allow-list in this
// repository was taken off a summary, and it dropped SVG's `script` and opened
// a hole. A property quietly missing here is a lint that fires on correct code;
// one quietly gained is a lint that stays silent on a typo. Neither is worth a
// transcription.
//
// The source is `ed/idl/` in w3c/webref — IDL that Reffy extracted from each
// spec's own text, so it cannot disagree with the prose the way a transcription
// can. `WEBREF_COMMIT` pins it: a moving `main` would mean the committed .mbt
// and this script silently stop corresponding.
//
// To pick up a spec change: bump WEBREF_COMMIT, re-run, and commit the pin
// together with the regenerated file. Read the diff.
//
// Run:  node scripts/fetch-dom-props.mjs
//
// `--check` regenerates into memory and compares, with the same caveat the
// sanitizer generator carries: this emits UNFORMATTED MoonBit and the committed
// file has been through `moon fmt`, so a byte difference is not proof the specs
// changed. The honest check is the `dom-props` task, which formats first.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// w3c/webref, pinned. 2026-08-19.
export const WEBREF_COMMIT = "b706309000d646ba04ab2dcd79b4967db547f4cf";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "render/dom_props_gen.mbt");

const RAW = (f) =>
  `https://raw.githubusercontent.com/w3c/webref/${WEBREF_COMMIT}/ed/idl/${f}`;

// The specs an event path can reach. Every one is fetched whole and parsed
// whole; what is KEPT is decided by the closure below, not by this list, so
// adding a spec here can only widen what the table knows about and never
// changes what it says about something it already knew.
const SPECS = [
  "dom.idl",             // Event, EventTarget, Node, Element, DOMStringMap
  "uievents.idl",        // UIEvent, Focus/Input/Keyboard/Mouse/Wheel/Composition
  "pointerevents.idl",   // PointerEvent
  "touch-events.idl",    // TouchEvent, Touch, TouchList
  "html.idl",            // HTMLElement and its hundred children, DataTransfer
  "clipboard-apis.idl",  // ClipboardEvent
  "cssom-view.idl",      // Element's scroll/client geometry, as partials
  "FileAPI.idl",         // File, FileList
  "wai-aria.idl",        // ARIAMixin, which Element includes
  "cssom.idl",           // ElementCSSInlineStyle and LinkStyle, both included
];

// What the table covers, and it is a decision worth stating.
//
// Every interface that inherits from `Event` — that is the path's ROOT — plus
// every interface that inherits from `Element`, because `target`,
// `currentTarget` and `relatedTarget` are what an allowlisted object step lands
// on in practice. Plus the handful of leaf types those steps reach.
//
// `Window` and `Document` are deliberately ABSENT, and their absence is not an
// oversight: no allowlisted step lands on either, so
// `e.target.ownerDocument.defaultView` has no typed continuation here — which
// is a second reason that path is refused, after the allowlist's first.
const ROOTS = ["Event", "Element"];
const EXTRA = [
  "DataTransfer",
  "DataTransferItem",
  "DataTransferItemList",
  "DOMStringMap",
  "FileList",
  "File",
  "Blob",
  "Touch",
  "TouchList",
];

async function getText(f) {
  const res = await fetch(RAW(f));
  if (!res.ok) throw new Error(`${f}: HTTP ${res.status}`);
  return res.text();
}

// --- the reader -------------------------------------------------------------
//
// A focused reader over machine-GENERATED IDL, not a WebIDL parser. It reads
// three shapes — `interface`, `partial interface`, `includes` — and inside an
// interface body it reads `attribute` lines and SKIPS the rest.
//
// It is strict about the two things that could go wrong silently. An attribute
// line it cannot take apart THROWS rather than being dropped, because a dropped
// property is a lint that fires on correct code. And an `includes` naming a
// mixin no spec here defines throws too, because a missing mixin is a whole
// group of properties absent with nothing to show for it.

/** Strip comments and extended attributes that would confuse the line reader. */
function scrub(idl) {
  return idl
    .replace(/\/\/[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
}

/** Every `interface`/`interface mixin`/`partial interface` body in a file. */
function* blocks(idl) {
  const re =
    /(partial\s+)?interface\s+(mixin\s+)?([A-Za-z0-9_]+)(\s*:\s*([A-Za-z0-9_]+))?\s*\{/g;
  let m;
  while ((m = re.exec(idl)) !== null) {
    // Brace matching from the opening `{`: an interface body has no nested
    // braces in webref's output except in default values, which the counter
    // handles anyway.
    let depth = 1;
    let i = re.lastIndex;
    while (i < idl.length && depth > 0) {
      if (idl[i] === "{") depth++;
      else if (idl[i] === "}") depth--;
      i++;
    }
    yield {
      partial: Boolean(m[1]),
      mixin: Boolean(m[2]),
      name: m[3],
      inherits: m[5] ?? null,
      body: idl.slice(re.lastIndex, i - 1),
    };
    re.lastIndex = i;
  }
}

/** The attribute declarations in one interface body. */
function attributes(body, where) {
  const out = [];
  for (const raw of body.split(";")) {
    const line = raw.trim().replace(/\s+/g, " ");
    if (!line || !/(^|\s)attribute\s/.test(line)) continue;
    // `[SameObject] readonly attribute DOMTokenList classList`
    const m = line.match(
      /^(?:\[[^\]]*\]\s*)?(?:inherit\s+|static\s+|stringifier\s+|readonly\s+)*attribute\s+(.+?)\s+([A-Za-z0-9_]+)$/,
    );
    if (!m) {
      throw new Error(
        `${where}: cannot read this attribute declaration — ` +
          `"${line}". A dropped property is a lint that fires on correct ` +
          `code, so this refuses rather than skipping.`,
      );
    }
    out.push({ type: m[1].trim(), name: m[2] });
  }
  return out;
}

/** `A includes B;` pairs. */
function* includes(idl) {
  const re = /^\s*([A-Za-z0-9_]+)\s+includes\s+([A-Za-z0-9_]+)\s*;/gm;
  let m;
  while ((m = re.exec(idl)) !== null) yield { host: m[1], mixin: m[2] };
}

// --- the type map -----------------------------------------------------------
//
// Three kinds cross an `e.` boundary as themselves, and everything else is an
// object. That is the design's rule, not this script's: an `e.` path always
// produces a `Value`, and a leaf that is not representable is `Null`.

const TEXT = new Set(["DOMString", "USVString", "ByteString", "CSSOMString"]);
const NUM = new Set([
  "long", "unsigned long", "short", "unsigned short",
  "long long", "unsigned long long",
  "double", "float", "unrestricted double", "unrestricted float",
  "byte", "octet",
]);

function kindOf(type) {
  // Two things are stripped, and neither changes what the leaf IS.
  //
  // An extended attribute on the type — `[LegacyNullToEmptyString] DOMString`,
  // which is how `HTMLInputElement.value` is spelled — says what happens when
  // JavaScript assigns null to it. An `e.` path only ever READS.
  //
  // And nullability: a path that does not resolve is `Null` either way, so
  // `Window?` and `Window` are the same question here.
  const t = type
    .replace(/^\[[^\]]*\]\s*/, "")
    .replace(/\?$/, "")
    .trim();
  if (TEXT.has(t)) return ["PText", null];
  if (NUM.has(t)) return ["PNum", null];
  if (t === "boolean") return ["PBool", null];
  // Everything else is an object of some named type — an interface, a
  // sequence, an enum, `any`. Layer 2 refuses to traverse one unless the STEP
  // is on the allowlist, and the name is what lets it ask.
  return ["PObj", t];
}

const lit = (s) => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;

export async function generate() {
  const sources = [];
  for (const f of SPECS) sources.push([f, scrub(await getText(f))]);

  // Pass 1: the SHAPE of every declaration — name, inheritance, and the body
  // text, unparsed. Bodies are read in pass 4, and only for what is kept.
  //
  // Deferring that is what lets the reader stay strict. The specs fetched here
  // carry interfaces this table has no business in — `CSSPageDescriptors`
  // declares `attribute [LegacyNullToEmptyString] CSSOMString margin-top`, a
  // shape nothing an event path reaches ever uses — and refusing to read one of
  // those would be the generator failing on something it was never going to
  // say anything about. Strictness belongs where the output is.
  const ifaces = new Map(); // name -> { inherits, bodies: [[where, text]] }
  const mixins = new Map(); // name -> [[where, text]]
  const get = (n) => {
    if (!ifaces.has(n)) ifaces.set(n, { inherits: null, bodies: [] });
    return ifaces.get(n);
  };
  for (const [file, idl] of sources) {
    for (const b of blocks(idl)) {
      const where = `${file}: ${b.name}`;
      if (b.mixin) {
        if (!mixins.has(b.name)) mixins.set(b.name, []);
        mixins.get(b.name).push([where, b.body]);
        continue;
      }
      const it = get(b.name);
      if (b.inherits) it.inherits = b.inherits;
      it.bodies.push([where, b.body]);
    }
  }

  // Pass 2: the closure. Everything that reaches a ROOT by inheritance, plus
  // the named extras.
  const keep = new Set();
  const reaches = (n) => {
    const seen = new Set();
    let cur = n;
    while (cur && !seen.has(cur)) {
      if (ROOTS.includes(cur)) return true;
      seen.add(cur);
      cur = ifaces.get(cur)?.inherits ?? null;
    }
    return false;
  };
  for (const n of ifaces.keys()) if (reaches(n)) keep.add(n);
  for (const n of EXTRA) {
    if (!ifaces.has(n)) {
      throw new Error(
        `EXTRA names ${n}, which no fetched spec defines — the list and SPECS ` +
          `have drifted apart.`,
      );
    }
    keep.add(n);
  }

  // Pass 3: which mixins the kept interfaces include. A mixin nobody defines is
  // a whole group of properties silently absent, so it throws — but only for a
  // host the table keeps, because a mixin on `Window` is none of this table's
  // business and its spec is not fetched.
  const included = new Map(); // host -> [mixin]
  for (const [file, idl] of sources) {
    for (const { host, mixin } of includes(idl)) {
      if (!keep.has(host)) continue;
      if (!mixins.has(mixin)) {
        throw new Error(
          `${file}: ${host} includes ${mixin}, which no fetched spec defines. ` +
            `Add the spec to SPECS — a missing mixin is a whole group of ` +
            `properties absent with nothing to show for it.`,
        );
      }
      if (!included.has(host)) included.set(host, []);
      included.get(host).push(mixin);
    }
  }

  // Pass 4: read the bodies of what is kept, own declarations first so an
  // interface's own property wins over one a mixin brings.
  for (const n of keep) {
    const it = ifaces.get(n);
    it.props = new Map();
    for (const [where, body] of it.bodies) {
      for (const a of attributes(body, where)) it.props.set(a.name, a.type);
    }
    for (const mx of included.get(n) ?? []) {
      for (const [where, body] of mixins.get(mx)) {
        for (const a of attributes(body, where)) {
          if (!it.props.has(a.name)) it.props.set(a.name, a.type);
        }
      }
    }
  }

  const names = [...keep].sort();
  const rows = [];
  let props = 0;
  for (const n of names) {
    const it = ifaces.get(n);
    const inh = it.inherits && keep.has(it.inherits)
      ? `Some(${lit(it.inherits)})`
      : "None";
    const entries = [...it.props.entries()].sort((a, b) =>
      a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0,
    );
    props += entries.length;
    const fields = entries
      .map(([p, t]) => {
        const [kind, obj] = kindOf(t);
        const val = obj === null ? kind : `${kind}(${lit(obj)})`;
        return `      (${lit(p)}, ${val}),`;
      })
      .join("\n");
    rows.push(
      `  (${lit(n)}, { inherits: ${inh}, props: [\n${fields}\n    ] }),`,
    );
  }

  return `// Generated by scripts/fetch-dom-props.mjs — DON'T EDIT IT.
//
// Source: w3c/webref ed/idl, at commit ${WEBREF_COMMIT}.
// Specs: ${SPECS.join(", ")}.
//
// ${names.length} interfaces, ${props} properties. Kept: everything that
// inherits from ${ROOTS.join(" or ")}, plus ${EXTRA.join(", ")}.
//
// \`Window\` and \`Document\` are deliberately absent. No allowlisted object step
// lands on either (\`render/event_paths.mbt\`), so a path through one has no
// typed continuation here — which is the second reason it is refused, after the
// allowlist's first.

///|
/// What an \`e.\` path's leaf converts to.
///
/// Three kinds cross the boundary as themselves. Everything else is an OBJECT
/// of some named type, and the name is what lets layer 2 ask whether the STEP
/// is one it may traverse — the design's rule that every step is allowlisted,
/// not just the root.
pub(all) enum DomPropTy {
  PText
  PNum
  PBool
  PObj(String)
} derive(Eq, @debug.Debug)

///|
/// One interface: what it inherits, and what it declares.
///
/// Declares, not carries — an inherited property is found by walking
/// \`inherits\`, which is what \`dom_prop_ty\` does. Flattening here would have
/// made the table several times larger and said nothing more.
pub(all) struct DomInterface {
  inherits : String?
  props : Array[(String, DomPropTy)]
}

///|
/// Every interface an event path can reach, sorted by name.
pub let dom_interfaces : Array[(String, DomInterface)] = [
${rows.join("\n")}
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
        `difference here is not proof the specs changed. Run the dom-props task\n` +
        `instead — it formats before comparing.`,
    );
    process.exit(1);
  }
  console.log("dom props are up to date");
} else {
  writeFileSync(OUT, out);
  console.log(`wrote ${OUT}`);
}
