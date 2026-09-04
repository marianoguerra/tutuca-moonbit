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

## Known: a component from ANOTHER module does not respond to clicks

Placement works everywhere. A `Grid` from `std` holding a `Counter` from another
module renders correctly, at any depth. What fails is *interacting* with a
component whose module is not the module of the thing holding it.

It is narrow, and the boundaries are worth writing down because they were each
measured rather than assumed:

| holder | held | dispatch |
|---|---|---|
| host (`Shell.canvas`) | guest (`std`'s `Hole`) | **works** — the `+`, the `x` and the badge all dispatch |
| guest (`std`'s `Hole`) | guest, same module (`std`'s `Textarea`) | **works** — typed text survives two full re-renders, so the successor is written back through the holder |
| guest (`std`'s `Hole`) | guest, another module (`Counter`) | **fails** — no transition, no re-render |

So it is not "a guest cannot dispatch" and not "a guest under a host component
cannot dispatch". It is the cross-module hop, which puts it in the same family
as the two bugs this branch opened by fixing — the per-module handle table and
the marker that named a component without naming its module.

Reproduce: press `edit`, press `+`, pick `Counter` (load it from the library
first), press `edit` again to leave editor mode, then press the counter's `+`.
The count stays at 0.

**It is not the host.** `tgc/host/host_test.mbt` now has the headless version of
exactly this — two modules registered into one scope, a `Shelf` from one holding
a `Counter` from the other, mounted and clicked — and it passes: the counter
answers, and the successor is written back through a holder whose module has
never heard of it. Two in-process fakes, no wasm.

So the remaining fault is in the bridge between that host and a compiled card,
and the two ends that are already proved narrow it further:
`tgc/test/compose-guest.test.mjs` holds a component from one module inside
another and reads and writes through it at the `__cardguest` surface. What is
left is the seam between those two proofs — a card's `get_field` answering a
`$dyn` marker, that marker being wrapped back into a `DynObj`, and dispatch
finding a handler on it.

Deliberately not guessed at from the browser. The next step is a headless
two-card repro through `tutucard/guest` — the same shape as the host test above,
with real compiled modules in place of the fakes.
