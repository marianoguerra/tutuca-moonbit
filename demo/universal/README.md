# universal — composition, as a demo

A page where a `+` opens a palette, you pick something, and it appears. What
makes it worth having is what is *not* in it: **the canvas holds no host
components at all.** The layout kit — `Hole`, `Box`, `Grid`, `Tabs`, `Text`,
`Textarea`, `Markdown` — is an ordinary tutucard compiled by `tgc/emit` and
registered by `register_module`, exactly like a card you paste into the box at
the bottom of the page. The palette cannot tell them apart because there is
nothing to tell.

```
just universal          # build + assemble dist/universal/
just serve              # or: python3 -m http.server --directory dist
```

then open `/universal/`, or `/universal/?loadAll` to load every sample card at
boot instead of picking them from the library.

## The pieces

| where | what |
|---|---|
| `std/std.card.html` | the layout kit, and the three protocols |
| `catalog/` | palette rows built from manifests; ranked search that says why |
| `compose/` | the bottom-up builder |
| `ui/` | the shell, the picker, the cell memory — target-agnostic, driven on the in-memory DOM |
| `.` | the page: the registry, the compiler, the app |

## What a test cannot see

Most of this is checked headlessly — 13 tests over the shell, 7 over the
builder, 10 over the catalog, 4 over the kit's manifest, and 8 scenes inside the
card itself. Four things are not, and each needs a browser:

- **The chrome's reserved band.** `pt-5` on `Hole:chrome` is what keeps the
  badge and the `x` from sitting on top of what is held and *intercepting its
  clicks*. There is no layout in the in-memory DOM, so nothing there overlaps
  and nothing there fails.
- **File drop.** The listener is on `document`, outside the tutuca tree — `drop`
  is the only DOM event that crosses component boundaries, so a hole claiming it
  would swallow the page-wide drop.
- **`?loadAll` timing** — eleven cards compiling at once, while the page draws.
- **The localStorage round trip**, across a real reload.

## Known: a placed guest does not respond to clicks

Placement works — a `Grid` from `std` holding a `Counter` from another module
renders correctly, at any depth. **Interacting with the placed component does
not:** clicking the Counter's `+` produces no transition and no re-render.

It is specific. Dispatch reaches host components on the same page (the shell's
own buttons work), and a guest mounted as the app *root* works — that is what
the card playground does. What fails is a guest held in a **host component's
field**, which is what `Shell.canvas` is.

Reproduce: load the page, press `edit`, press `+`, pick `Counter`, then press
the counter's `+`. The count stays at 0.

Not diagnosed further, and deliberately not guessed at: the composition claim
this demo exists to make is about placement and rendering, and those are
verified end to end. This is a separate defect in the dispatch path and it wants
its own repro before its own fix.
