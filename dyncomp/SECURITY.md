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
| guest views (tutuca templates) | the host's DOM | **handled** — a Sanitizer-API port over the tree at registration, plus URL-scheme and event-handler rules at render; raw markup still refused outright |
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
them that way (`dyncomp/host/wasm/loader.mjs`):

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

A browser host chooses its tier through `@uiw.mount(policy=…)`, or
`@dhw.set_app(…, policy~)` for a page that does its own mounting; `set_policy`
changes it afterwards, for a host that asks a person first. It applies at LOAD,
so narrowing it does not retract a bundle already registered — revoking is
dropping the bundle. Until 0.9.6 there was no such argument and the browser host
registered everything as untrusted no matter what the page wanted, which made
the two upper tiers reachable only from a test.

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

**Where the refusal is weaker than it sounds.** `has_raw_html`
(`anode/classes.mbt`) walks `ANode::for_each_child`, and that walk has two blind
spots on an unexpanded tree. A `MacroCall`'s `node` is `None` until
`ParseContext::compile` expands it, so a macro BODY is never visited; and
`MacroData.slots` — the caller's own subtrees, keyed by slot name
(`parse_context.mbt`, `new_macro_node`) — is not in `for_each_child` at all, so
a slot's content is never visited either, expanded or not.

The second one is reachable from a guest: `<x:card><div
@dangerouslysetinnerhtml=".payload"></div></x:card>` passes `check_view` with no
refusal. It only RENDERS if the host registered a macro named `card` whose body
places the slot — guest views compile against the host's `ComponentStack`
(`component/scope.mbt`, `lookup_macro`), so this is contingent on the host having
macros rather than unconditional. It is still the walk being wrong rather than
the policy being right, and the sanitizer walk below must not inherit it.

**What is next.** Port the [WHATWG Sanitizer
API](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#sanitizer)
config model to anode: a `SanitizerConfig` of `elements` / `removeElements` /
`replaceWithChildrenElements` / `attributes` / `removeAttributes` / `comments` /
`dataAttributes`, with per-element attribute rules on the `elements` entries
(the spec's `SanitizerElementNamespaceWithAttributes`; `removeElements` and
`replaceWithChildrenElements` entries carry none). The design is
[`docs/sanitizer.md`](../docs/sanitizer.md).

Following the spec's shape rather than inventing an allowlist means the default
is the one the platform already argues is safe, and the same config can later be
handed to the native `Element.setHTML()`.

**But the Sanitizer API does not answer the URL-scheme question, and an earlier
version of this section said it did.** URL schemes are out of scope for that
spec: its unsafe baseline is about script-bearing ELEMENTS (`script`, `iframe`,
`object`, `embed`, `frame`, `use`, `base`) and event-handler ATTRIBUTES, and its
own default configuration explicitly allows `href` on `<a>`. `<a
href="javascript:…">` survives `setHTML()` with the default sanitizer intact.
The platform's answer to that half is CSP and Trusted Types, neither of which is
a thing anode can port.

So the port buys the element and attribute-NAME layer and nothing else, and
tutuca needs a second mechanism for attribute VALUES. It cannot run where the
config does: an attribute value in a view is a `Val` expression
(`AttrItem::Plain`), so what it will hold is unknowable at registration for the
same reason `RawHtml`'s payload is.

It runs a step later, as a filter between `@render.render_root` and
`@vdom.render` (`app/loop.mbt`, `App::render_now`) — the point where the tree is
concrete and nothing has touched the DOM yet. `@filter.UrlFilter` is that rule:
it drops an attribute whose URL scheme executes, normalizing the way a browser
does first (`java&#9;script:` is `javascript:`), and records what it dropped
since by then there is no author to tell.

**One NAME rule runs there too, and not only for values.**
`@filter.HandlerFilter` drops `on*` attributes off the tree before the diff,
which duplicates what `check_view` already refuses at registration. That is
deliberate rather than redundant: the static pass is the thing being defended,
and a rule that only holds when another pass already held is not a second layer.
It also covers a case nothing else does — `set_prop` routes by
`has_property`, and on a plain HTML element assigning a string to `.onclick`
is inert, but `uses_prop` is `!namespaced && …` (`vdom/to_dom.mbt`), so an SVG
or MathML element routes every attribute through `set_attribute` and
`<svg onclick="…">` reaches the DOM as a live content attribute. There is no
accident of routing saving that one.
`@filter.Baseline` is the two rules in a single traversal, and is what `set_app`
installs.

**Every tutuca app installs one, not only a page that hosts bundles.**
`App::new` installs `@filter.Baseline` — the URL rule and the handler rule in
one traversal — and `set_filter(None)` is the opt-out. Not tier-dependent,
because there is no legitimate `javascript:` URL in a described view at any
tier.

This glue used to install its own, from when the seam defaulted to absent. It no
longer does: two filters would mean reports split across two logs, and the app's
own is installed before `set_app` is ever called. What stays here is
`take_filter_reports()`, which drains the app's — by render time there is no
author to tell, so a page that wants to say "this component tried to render a
`javascript:` URL" reads it from there.

That also retires an honest limit this section used to carry. The install was
one line inside the wasm glue, which `moon test` never runs, so it was verified
by inspection like the rest of the `tcomp` bridge. It is now in `App::new`,
which the suite exercises directly (`app/filter_test.mbt`).

**Raw markup is refused by default, and a host can now grant it.**
`vdom/filter/markup` sanitizes a payload against the same `SanitizerConfig` and
hands back described NODES — never a string, because a sanitized string that the
browser parses a second time is the mutation-XSS vector that has bitten every
sanitizer which shipped that shape.

What used to be missing was a way for `Policy::check_view` to know that a host
had installed that filter: a policy saying `raw_markup: true` beside an app
mounted without it would send the payload straight to `set_inner_html`
unchecked. So the permission and the filter are now derived from the SAME value.
`Policy` carries a `Sanitizer`; `Policy::with_sanitizer(config)` replaces it;
and `@markup.filter_for(policy.sanitizer)` returns the filter that sanitizer
requires — the markup filter in front of `Baseline` when raw markup is
permitted, `Baseline` alone when it is not. `set_app` calls it, so a host cannot
hold the permission without the filter.

It is a function rather than a type-level proof because `dyncomp/policy` is a
leaf over `anode` and must not import `vdom` — the permission cannot carry
evidence about a filter without inverting that. What is available is to make one
function the only place the two are named together, and to test it from both
sides (`vdom/filter/markup/install_test.mbt`).

The default is unchanged: every tier's sanitizer refuses raw markup, so a guest
that has not been explicitly granted it is refused at registration exactly as
before. Granting it is one call a host makes deliberately, which was the point.

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
`tutuca:component@0.5.0` has no field that reaches `global_style`, and the WIT
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

## 7. `persist` / `restore`: the host stores bytes it never reads

`instance.persist` hands the host a `list<u8>` and `[static]instance.restore`
takes it back. The host stores it and returns it; it does not parse it. That is
the point — a guest keeps what its declared fields do not name — and it has
three consequences worth stating.

**The bytes are the guest's, and so is the risk.** A bundle that reads its own
bytes badly can only hurt itself: `restore` returns `option<instance>`, so a
refusal is a supported answer, and a guest that traps takes down nothing but
its own call. The host has a second way in either way — `Snapshot.fields`, the
declared-field projection it made itself — so a component whose format changed
comes back rather than disappearing.

**A store is untrusted input.** `Snapshot::from_json` treats everything in it
that way: text that is not a snapshot reads as none, and base64 that will not
decode reads as "no guest bytes" rather than as a failure. Anything else on the
origin can write to `localStorage`, so what comes out of it is exactly as
trustworthy as what comes off the network.

**Storage is a channel, and it is the page's.** `dyncomp/persist` names no
backend; the browser one (`dyncomp/persist/wasm`) is the page's own
`localStorage` under a prefix the page chooses. A guest cannot reach it — there
is no storage capability, and `persist` is a value the host asked for rather
than a call the guest makes. Two bundles cannot read each other's snapshots
through the contract; whoever hosts them decides what the store holds and what
is handed back.

## 8. Provenance

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
