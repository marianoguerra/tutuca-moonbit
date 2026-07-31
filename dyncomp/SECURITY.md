# What a dyncomp bundle can and cannot do

The premise of `dyncomp/` is that a component can be fetched from anywhere and
mounted into a running app. That is only worth building if it is possible to say
precisely what such a component may do. This document says it — the parts that
are already true, the parts that needed work, and what is still open.

Everything below was checked against the code, with file and line references.
Where a claim is weaker than it sounds, it says so.

## Summary

| Channel | Reaches | State |
|---|---|---|
| wasm imports (`values`, `control`) | nothing ambient | **safe by construction** |
| `env` (clock, randomness, ids) | weakened, host-supplied answers | **gated** — capability-granted, refused by default |
| guest views (tutuca templates) | the host's DOM | **partly handled** — raw markup refused; a sanitizer is next |
| guest CSS (`component-def.style`) | the host's stylesheet | **partly handled** — refused outright for an untrusted bundle; unvalidated above that |
| `control.request` → host handlers | the host's own services | **open** — needs caller-aware authorization |
| a hung or runaway guest call | the page's responsiveness | **open** — needs worker isolation |

The decisions live in [`policy/`](policy/) and are enforced by
`register_bundle` before it parses anything; `policy/policy_test.mbt` is the
executable form of most of this document.

## 1. The wasm sandbox

`world dynamic-component` imports exactly three interfaces and no WASI
(`wit/tutuca-component.wit`). A guest therefore has **no** filesystem, network,
sockets, environment variables, subprocesses, storage, or — except through
`env`, below — clock and entropy. It cannot reach the DOM at all: tutuca has no
element event handlers, so a view is a description rather than a place to put
code, and the guest renders nothing.

That is stronger than the usual "it's sandboxed, it's wasm". Several specific
properties follow from the contract's shape rather than from the wasm engine:

- **Control calls are buffered, not performed.** Everything in `control` except
  `log` is collected during `handle-event` and applied by the HOST afterwards,
  through the dispatching `&Ctx` (`host/dynobj.mbt`, `obj_handler`). The guest
  does not act; it asks, and the host chooses.
- **Paths are relative only.** `send-at` / `bubble-at` address the dispatching
  instance's own subtree. Absolute paths are deliberately absent from the WIT,
  so a component cannot address the tree it happens to be mounted in.
- **`make-instance` is same-bundle only**, in the host-assigned token space.
- **Arena handles die at the call boundary**, so nothing a guest captured stays
  reachable after it returns.
- **The type table is depth-guarded** at 16 (`host/manifest.mbt`,
  `ty_info_at`), because a manifest that crossed a trust boundary cannot be
  trusted to be acyclic.
- **No clock meant no measurement.** Before `env`, a guest could not read time
  at all, which removes the primitive most timing side channels are built from.
  `env` is the deliberate, bounded relaxation — see below.

## 2. `env`: clock, randomness and ids, on purpose

Components genuinely need "what time is it" and "give me a fresh key". The
answer is not `wasi:clocks` + `wasi:random`, for three reasons in order of
weight:

1. The world imports no WASI, and adding it drags preview2 shims into the
   browser that nothing else needs.
2. A real monotonic clock is exactly the primitive a timing side channel is
   built from.
3. An ambient clock makes a dispatch unreplayable, which contradicts the first
   principle of this design — *the host is the framework*.

So `env` gives deliberately weaker answers, and the browser bridge implements
them that way (`demo/wasm-loader-lib.mjs`):

- `now-ms` is **coarsened to a second and frozen for the duration of one call**.
  Every read inside one handler agrees, which is what lets a dispatch replay and
  what denies a guest a fine-grained timer.
- `random-u64` draws from a **seeded xorshift**, not `crypto.getRandomValues`. A
  session that records its seed replays exactly. It is explicitly not
  cryptographic: a guest that needs unpredictability an attacker cannot
  reproduce asks the host through `control.request`.
- `new-id` is monotonic per bundle — for keying a list, not for naming anything
  outside the page.
- `control.after` lets a guest ask for a later message. The host owns the timer
  and may coalesce, delay or drop it; there is no cancel, because a guest cannot
  cancel what it does not own.

Each is gated by a capability the manifest requests (`cap-clock`, `cap-random`,
`cap-timer`) and the host grants. An ungranted capability **refuses the bundle**
rather than degrading it: a capability that is present but lies is worse than
one that is absent — a guest reading a frozen zero from an ungranted clock
cannot tell that from midnight.

The default policy (`Policy::untrusted()`) grants **none** of them, and
`register_bundle` enforces that before it parses anything. `Policy::granted()`
— a person said yes to this bundle — adds the clock and ids but still not the
timer: a bundle that wants to wake itself up is asking for something nobody can
meaningfully consent to in one dialog.

Two gaps remain on this path, both marked in the code: the browser bridge
supplies `env` unconditionally rather than per grant (harmless while jco elides
an import no guest calls), and `control.after` has no host implementation at
all — the bridge warns rather than crashing, because an absent import makes jco
throw something that says nothing about why.

`control.request` is deliberately *not* a capability — see §5.

## 3. Guest views: raw markup is refused

**The finding.** `anode/attrs.mbt` parses `@dangerouslysetinnerhtml` into a
`RawHtml` attribute item, and `vdom/to_dom.mbt` routes it to
`node.set_inner_html(html)`. There is no tag allowlist and no attribute
allowlist anywhere in `anode/` or `vdom/`: `create_element` takes the tag
verbatim (`vdom/dom_trait.mbt`) and `set_attribute` the name verbatim
(`vdom/to_dom.mbt`). A guest view is text the host compiles and renders into its
own page, so this was a way out of the wasm sandbox through a channel that never
touches wasm.

**What is true now.** A guest view containing `RawHtml` is **refused at
registration** — `Policy::check_view`, called from `host/bundle.mbt`'s
`screen_view` over the predicate `@anode.ANode::has_raw_html`. Not
tier-dependent: a `System` bundle is part of the app and writes its views the
ordinary way, so nothing is losing anything.

Two details matter about that refusal:

- It cannot be a sanitize-at-parse-time fix. `RawHtml` carries a `Val` — an
  expression — so what it will hold is not knowable until render, and by then
  the markup is in the document. Refusing the *construct* is the only decision
  available ahead of time.
- It happens over the **shadow parse** the linter already does, before anything
  is registered. Deciding after `compile()` would mean the components were
  already in the shared registry, contributing event names and CSS classes to
  the page that turned them down. There is a test for exactly that.

**What is next.** Port the [WHATWG Sanitizer
API](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#sanitizer)
config model to anode: a `SanitizerConfig` of `elements` / `removeElements` /
`replaceWithChildrenElements` / `attributes` / `removeAttributes` / `comments` /
`dataAttributes`, with per-element attribute rules and the spec's `removeUnsafe`
baseline. Two application points — over the compiled ANode tree at registration
(which subsumes the tag, attribute and URL-scheme problem uniformly), and at
`set_inner_html` time, which is what would let raw markup back in safely.

Following the spec's shape rather than inventing an allowlist means the default
is the one the platform already argues is safe, and the same config can later be
handed to the native `Element.setHTML()`.

## 4. Guest CSS: no global stylesheet, and a validator to come

**The finding, and a correction.** A guest's `component-def.style` rides on the
`"main"` **view's** style, not on `common_style` (`host/bundle.mbt`), and
`Component::compile_style` emits it as
`[data-cid="N"][data-vid="main"]{<style>}` by string concatenation
(`component/component.mbt`). A `style` of `} html { … } .x {` closes the wrapper
and applies globally.

`global_style` — emitted verbatim and unscoped by the same function — is **not
reachable by a guest**: `Component::for_type` defaults it to `""` and
`register_bundle` never passes it.

**What is true now.** Two things.

No global CSS for guests, as an invariant of the contract:
`tutuca:component@0.3.0` has no field that reaches `global_style`, and the WIT
says so where the `style` field is defined. Unscoped CSS from a bundle would
reach the page around it, and no amount of validation makes that safe.

And an **untrusted bundle ships no CSS at all** — `Policy::check_style` refuses
a non-empty `style` at the default tier, on the grounds that a bundle should
style with the host's utility classes, which the host compiles and which
therefore cannot break out of anything. All three sample guests already do
exactly that, so the strict default costs nothing real.

Above that tier the block is currently accepted **unvalidated**, and that is a
known gap rather than a decision: `allow_custom_css` today means someone
vouched for the bundle, not that anything checked it.

**What is next**, and what would turn `allow_custom_css` into a real check. A
validator for the scoped block, built on
[`mizchi/css`](https://mooncakes.io/docs/mizchi/css) rather than hand-rolled:
`mizchi/css/token` + `mizchi/css/parser` parse it as a declaration list and
`mizchi/css/diagnostics` carries the errors. Parsing and **re-serializing**,
instead of concatenating the raw string, is what structurally kills the
brace-breakout; the validator then also rejects `@import` and screens `url()`
targets, which are the egress channel.

The stricter tier that would have been the other half of this is already in
place — see "what is true now" above.

## 5. `control.request`: a bundle's own handlers are fine, the host's are not

A request resolves against the bundle's own handlers first, then the host's:
`register_bundle` puts the bundle's in a child scope and `lookup_request` walks
child → parent.

**A bundle's own handlers need no policy.** They run inside the guest, which has
no dangerous capability, so they inherit exactly the same limitation as every
other line of guest code. Nothing to add.

**Host-registered handlers are the open one.** A guest can currently call any of
them with any arguments. In `demo/universal_wasm` those are `double`,
`listComponents`, `makeComponent`; in a real app they are whatever the app's
services are.

The fix is not a manifest-declared allowlist — that would ask the untrusted
party what it is allowed to do. It is to authorize **at call time, from the
requester's path**, and let the host decide: the path already identifies the
caller, and a `DynObj` sitting at it names its bundle.

The plumbing gap is small and specific. `Transactor::push_request` already
carries the requester's `DispatchPath`, but
`RequestFn((Array[Value], (Result[Value, Value]) -> Unit) -> Unit)` never
receives it. Threading it through is a `component/` change, and it is the next
step here.

## 6. Availability

Guest calls are synchronous, so an infinite loop or a runaway `memory.grow`
inside `handle-event` freezes the tab. This is an availability problem, not a
confidentiality or integrity one, and the fix — instantiating guests in a Web
Worker so a hung call can be terminated — turns the whole `tcomp` bridge async.
It is recorded, not built.

Quotas on manifest size, view count, style length and type-table size are in
place (`Policy::check_quotas`), which bounds the manifest-bomb surface cheaply —
the host parses every view and compiles every component before it renders
anything, so a manifest with ten thousand views is a frozen tab. They are
generous by design: they catch a runaway, not an author. A per-bundle cap on
LIVE INSTANCES is not there yet, because it has to be enforced at
`make_instance` time rather than at registration.

## 7. Provenance

A bundle's identity should be the **hash of the archive it arrived in**, not
anything it says about itself. The manifest's `doc` / `version` / `homepage` /
`authors` are advisory and labelled as such in the WIT; nothing resolves against
them. Content-addressed bundle ids (SHA-256, computed in the JS loader) are the
next step, and signing is a step after that.

## What to check when changing this

- Adding a field to `component-def` or `manifest`: does anything you added reach
  `global_style`, or reach the DOM as text rather than as a description? Those
  are the two shapes that have gone wrong here.
- Adding to `control`: is it buffered and applied by the host, or does it act?
  Only `log` acts, and only because logging cannot be misused into anything.
- Adding to `env`: is the answer weaker than the platform's own, and is it
  frozen or seeded so a dispatch still replays?
