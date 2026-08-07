# Upstream provenance

- Repository: `https://github.com/mizchi/markdown.mbt`
- Version: `0.6.4`
- Commit: `e3055d1589e9e3444fd7565198c48509234ac5af` (2026-07-03)
- License: MIT, © 2024 mizchi — full text in `LICENSE.upstream`
- Vendored package: `src` (module `mizchi/markdown`)

Every `.mbt` file in this directory is a **verbatim copy** of the upstream file
of the same name. Nothing has been edited, and nothing should be: re-sync by
copying again. Only `moon.pkg`, this file and `LICENSE.upstream` are ours.

## What is vendored

15 of upstream's 29 production files, ~4,730 lines:

| Group | Files |
|---|---|
| AST + scanner | `types.mbt`, `scanner.mbt`, `unicode.mbt` |
| Block parser | `block_parser.mbt`, `_code`, `_frontmatter`, `_heading`, `_html`, `_link_def`, `_list`, `_table` |
| Inline parser | `inline_parser.mbt`, `_emphasis`, `_link`, `_strict` |

`block_parser_frontmatter.mbt` is here only because `block_parser.mbt` calls
`try_parse_frontmatter`; nothing else reaches it.

GFM is not separable from these files and comes along: tables
(`block_parser_table.mbt`), footnotes (`Block::FootnoteDefinition` /
`Inline::FootnoteReference`), strikethrough (`Inline::Strikethrough`) and task
lists (`ListItem.checked`).

## What is not, and why

Each was checked for inbound references from the files above and has none.

- `renderer.mbt`, `renderer_autolink.mbt` — AST → HTML **string**. Not wanted:
  `vdom/filter/markdown` walks the AST straight into vdom nodes, so no HTML text
  is ever built and the browser never re-parses one. See `docs/sanitizer.md`.
- `serializer.mbt`, `serializer_inline.mbt` — AST → markdown.
- `renderer_literal.mbt`, `renderer_literal_inline.mbt` — an editor-preview
  renderer emitting `<span class="md-…">` with source-position attributes.
- `incremental.mbt` — incremental reparse from an `EditInfo`.
- `plugin.mbt` — the syntax-highlighter hook; its highlighters are the reason
  upstream depends on `mizchi/syntree`.
- `bench*.mbt`, `*_test.mbt` — upstream's own harness. Dropping `bench*.mbt` is
  what lets `moon.pkg` omit `moonbitlang/core/bench`.
- `src/experimental/purify/` — a hand-rolled DOMPurify clone. This module has a
  sanitizer generated from the WHATWG spec's own machine-readable baseline
  (`anode/sanitize/`), and `AGENTS.md` forbids taking an allow-list from
  anywhere else.
- `src/api/`, `src/highlight_*`, `src/toc`, `src/slug`, `src/frontmatter`,
  `src/syntree_api`, the rest of `src/experimental/` — other packages entirely.

## Why vendored rather than depended on

The published `mizchi/markdown@0.7.4` declares `supported-targets: js+wasm` and
depends on `mizchi/moomaid` (mermaid), `moonbitlang/yacc`, `moonbitlang/parser`
and `mizchi/syntree`. None of those are reachable from the parser — they belong
to the highlight and experimental packages — but a module dependency takes the
whole graph, and this module's `preferred_target` is wasm-gc.

What is copied here has no third-party dependency and no `extern` declaration at
all, so it checks clean on wasm-gc, js and native.

## Re-syncing

Copy the 15 files listed above from a fresh checkout, update the commit and
version here, then run `moon run --target native cmd/dev -- ci`.
`markdown/parse_test.mbt` is ours rather than upstream's, and is the thing a
behavioural change in a re-sync has to get past.
