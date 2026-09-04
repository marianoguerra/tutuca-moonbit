# The card playground

A **card** is one `.html` file — spec, script, templates, styles, fixtures and
scenes — that the browser compiles to a component wasm module with no MoonBit
toolchain anywhere on the page. This directory is the machinery for that.

| | |
|---|---|
| `drive/` | the headless driver: mounts a card on memdom and runs its `<script type="tutuca/test">` scenes through `@harness`'s own verbs. SHIPS |
| `playground/` | the page's MoonBit half — `cardguest.mbt` implements `&Guest` over the JS surface, `host.mbt` is what the page calls |
| `web/` | the page itself: the shell, the `<mb-card>` element, the loader, the starter cards |
| `build/` | assembly and the four gates below |

## What ships to the page

`cmd/dev -- tutucard-playground` assembles `dist/tutucard/`. The payload is the
card compiler (`tgc/emit`), the Wax front end it stands on, and the page — plus
the two things a card can ASK for, each fetched lazily by whoever wants it:

- **`margaui.wasm`** — the class compiler the starter cards' `btn` / `card` /
  `badge` need, scoped to the preview (`web/margaui.js`). Compiling its own
  class names into CSS is the one thing a card does compile, and only when an
  element asks.
- **`editor.bundle.js`** — the shared CodeMirror. The page upgrades its own
  textareas once the first card is mounted; `?editor=plain` keeps the textareas,
  and an `<mb-card codemirror>` upgrades its own.

## The four gates

The assembly ends by CHECKING and COMPILING every card through the real entry
points, because the two card corpora are unreachable from `moon test`:

- `build/check-examples.mjs` — the starter cards, which are JS strings in
  `web/examples.js`, and the landing site's `playground/site/cards/*.html`,
  which are in no moon package;
- `build/run-tests.mjs` — every card's own scenes;
- `build/check-instances.mjs` — that instances the host holds are collected,
  both halves (see `tgc/host`);
- `build/check-regions.mjs` — `web/regions.js`, the offset arithmetic the
  structured view edits through, against its contract.
