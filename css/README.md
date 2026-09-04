# Stylesheets, and everything generated from an upstream

`css/` is the one place stylesheets live, and it is published — the wasm hosts,
the js playground and the native CLI all compile through it. This page is that
pipeline, plus the rule every generated-from-upstream table in the repo follows,
because they are the same rule.

## The two bundles

Split by provenance, regenerated together by `cmd/dev -- css-bundle`:

- `css/tailwind_bundle_gen.mbt` — stock Tailwind's `theme` / `preflight` /
  `utilities`, taken from the **`tailwindcss` npm tarball** at the version pinned
  in `scripts/fetch-tailwind.mjs`.
- `css/margaui_bundle_gen.mbt` — margaui's `base/`, `themes/` and `src/*.css`,
  from a clone at the ref pinned in `scripts/fetch-margaui.mjs`, with its `tw/*`
  dropped (`--skip-prefix tw/`).

## Generated from an upstream, elsewhere, same rule

- `anode/sanitize/spec_default_gen.mbt` — the WHATWG Sanitizer API's built-in
  default configuration, from the **machine-readable `builtins/` in the spec
  repo** at the commit pinned in `scripts/fetch-sanitizer-defaults.mjs`.
  Regenerate and verify with the `sanitizer-defaults` task, which does what
  `gen` does — regenerate, `moon fmt`, then diff. Prefer it to the script's own
  `--check`: that flag compares the generator's UNFORMATTED output against a
  file `moon fmt` has reformatted, so it reports "stale" on content that is
  byte-identical.

- `eventpath/dom_props_gen.mbt` — every property an event path can reach, with its
  type, from the **machine-extracted WebIDL in `w3c/webref`'s `ed/idl/`** at the
  commit pinned in `scripts/fetch-dom-props.mjs`. Regenerate with the
  `dom-props` task, which has the same three steps and the same `--check`
  caveat.

  It covers everything inheriting from `Event` or `Element`, plus the leaf types
  an allowlisted step lands on. `Window` and `Document` are deliberately absent,
  and that absence is load-bearing rather than an omission — see the generated
  file's header. The reader in the script is strict on purpose: an attribute
  declaration it cannot take apart THROWS rather than being skipped, because a
  dropped property is a lint that fires on correct code.

  It is a **type oracle and not a permission list**. Whether a step may be
  traversed at all is `eventpath/event_paths.mbt`'s question, and the two are
  separate because one is fetched and the other is argued.

- `anode/sanitize/css/properties_gen.mbt` — every CSS property the style
  sanitizer will let through, with what its value may contain, from the same
  `w3c/webref` extraction plus `mdn/data`, at the commits pinned in
  `scripts/fetch-css-properties.mjs`. Regenerate with the `css-properties`
  task, which has the same three steps.

## Vendored rather than generated, and equally not ours to edit

- `markdown/` — the CommonMark + GFM parser, copied verbatim from
  [mizchi/markdown.mbt](https://github.com/mizchi/markdown.mbt) at the commit
  pinned in `markdown/UPSTREAM.md` (MIT). 15 of upstream's 29 production files;
  the HTML renderer, serializer and incremental reparser are deliberately left
  behind, because `vdom/filter/markdown` walks the AST straight into vdom nodes
  and never builds an HTML string. **Do not hand-edit a file in there** —
  re-sync by copying again, and let `markdown/parse_test.mbt` (ours, not
  upstream's) fail if a behaviour the node builder depends on moved.

  It is vendored rather than depended on because the published
  `mizchi/markdown` drags `mizchi/moomaid` and declares `supported-targets:
  js+wasm`, while this module prefers wasm-gc. What is copied has no
  third-party dependency and no `extern` at all — `UPSTREAM.md` has the full
  reasoning and the list.

  **Never hand-transcribe an allow-list, and never take one from MDN or a blog
  post.** An entry quietly lost is a component that mysteriously fails to
  render; one quietly gained is a hole. `sanitize_test.mbt` holds
  `unsafe_elements` against the spec's own baseline for that reason.

**Take `tw/*.css` from npm, never from the margaui checkout.** margaui's own
`tw/README.md` calls its copies a manual mirror, and they lag upstream. The
compiler is ported from one exact tag
(`.mooncakes/marianoguerra/tailwindcss/UPSTREAM.md`), so the stylesheets must
come from that tag or the engine and its data disagree; `fetch-tailwind.mjs`
fails the build if the two pins drift apart. `compile_margaui` merges both maps,
so margaui resolves its `./tw/*` imports against the good copies.

`tutuca gen-tailwind-css` / `gen-margaui-css` are the build-time face of the same
pipeline: the class collection a host does at mount time, run over a project's
view files instead, so an AOT project can ship a static stylesheet. `tutuca watch
--margaui-css <file>` keeps that stylesheet current alongside the view modules —
`WatchPlan` carries a whole `CssPlan`, so it runs the same path rather than a
second implementation of it.
