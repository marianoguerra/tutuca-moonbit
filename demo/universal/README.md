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

## A card may declare `init`, and a host that skips it gets zeros

`tutucard/examples/Counter.html` puts its starting state in a `receive init`
(`step = 1`) rather than in its field defaults. A component built from the
schema's zeros therefore has a step of zero — it renders perfectly and adds
nothing per click, which reads exactly like a dispatch that never arrived.

So a placement sends `init` when the component declares one, and the catalog
carries whether it does. Worth knowing before writing another host: the symptom
of getting it wrong is not an error, it is a component that looks right and does
nothing.

It cost an afternoon of hunting a dispatch bug that did not exist. What settled
it was the ladder below — every rung passed, which left nowhere for a bug to be.

## What is proved, and at which level

Cross-module composition is one claim asked three times, because a proof at the
level that never had the bug is a proof about the wrong thing:

| where | what it drives |
|---|---|
| `tgc/test/compose.test.mjs` | the RUNTIME — a module holding another module's instance, which always worked |
| `tgc/host/host_test.mbt` | the HOST — two in-process fakes, two modules, one tree, one click |
| `tgc/test/twomod.test.mjs` | the SEAM — two really compiled modules registered into one scope, mounted and clicked, both by construction argument and by a `hold` message, because those are two different crossings; and the property door, which keeps a private field private through a holder |
