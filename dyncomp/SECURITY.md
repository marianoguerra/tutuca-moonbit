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
| archive code | page authority | **closed** — only descriptor bundles load; legacy JavaScript archives are rejected |
| archive parsing | page responsiveness/memory | **bounded** — compressed, expanded, entry and file-count limits; checked tar arithmetic and headers |
| wasm imports (`values`, `control`) | nothing ambient | **safe by construction** |
| `env` (clock, randomness, ids) | weakened, host-supplied answers | **gated** — capability-granted, refused by default |
| guest views (tutuca templates) | the host's DOM/network | **handled for untrusted bundles** — unsafe names, direct network sinks, raw markup/Markdown, guest-authored arbitrary utility CSS and URL-bearing macro arguments are refused; a CONSTANT inline `style` or SVG presentation attribute is parsed and re-emitted rather than refused (§4), while a dynamic one stays refused; `<img src>`/`<a href>` reopen only with `cap-external-urls`, and only to an origin settled before render — a literal the view states, or a config var the HOST bound (§3a); autonomous custom elements remain a host-code trust boundary |
| guest CSS (static manifest `style`) | the host's stylesheet | **partly handled** — refused outright for an untrusted bundle; unvalidated above that. The declaration half now has a validator (§4); the selector and at-rule half does not |
| `control.request` → host handlers | the host's own services | **open** — needs caller-aware authorization |
| a hung or runaway guest call | the page's responsiveness | **open** — needs worker isolation |

The decisions live in [`policy/`](policy/) and are enforced by
`register_bundle` before it parses anything; `policy/policy_test.mbt` is the
executable form of most of this document.

## 1. The wasm sandbox

`world dynamic-component` imports three callable interfaces plus the
types-only `tables` interface, and no WASI
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
- **The static manifest's type table is depth-guarded** at 16 (`host/manifest.mbt`,
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

Each is gated by a capability the static manifest requests (`cap-clock`,
`cap-random`, `cap-timer`) and the host grants. `cap-external-urls` (§3) is the
fourth name in that vocabulary and the one that gates no import at all: it is
about what a guest's VIEW may name, so it is checked at registration and the
module's import section has nothing to say about it. For v0.6 descriptor bundles,
the host-owned ABI also checks the core module's actual import section before
the first guest instruction runs: omitting a capability from metadata cannot
hide an import. An ungranted capability **refuses the bundle**
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

`control.after` still has no host implementation — the bridge warns rather
than crashing.

`control.request` is deliberately *not* a capability — see §5.

### Archive code is no longer a channel

Before v0.6, every archive carried jco's generated `*.component.js`, and the
loader imported it from a blob URL. Generated or not, that JavaScript ran with
the page's authority before wasm's import boundary could constrain it.

A descriptor archive instead contains `tutuca.json`, one core wasm module, and
HTML view files. [`host/wasm/abi.mjs`](host/wasm/abi.mjs) is the sole canonical-ABI
implementation and binds imports by name against the WIT-derived table. An
unknown import is refused before instantiation. An archive without
`tutuca.json` is rejected; the old `*.component.js` compatibility path no
longer exists, because warning before importing page-authority code is not a
sandbox.

Reaching the descriptor is bounded too (`host/wasm/loader.mjs`). Dropped files
are size-checked before `arrayBuffer`; fetched responses are counted while
streaming; gzip output is counted while decompressing; and tar parsing has
limits on expanded bytes, individual entries and file count. Tar sizes use
checked JavaScript numbers rather than a signed 32-bit coercion, headers have
their checksum verified, entries must advance within the input, and duplicate
basenames are rejected. `test/archive.test.mjs` holds the parser against the
former wraparound hang and compressed/expanded limit regressions.

## 3. Guest views: markup and browser egress are refused

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

**Where the refusal used to be weaker than it sounds.** `has_raw_html`
(`anode/classes.mbt`) walks `ANode::for_each_child`, and that walk has two blind
spots on an unexpanded tree. A `MacroCall`'s `node` is `None` until
`ParseContext::compile` expands it, so a macro BODY is never visited; and
`MacroData.slots` — the caller's own subtrees, keyed by slot name
(`parse_context.mbt`, `new_macro_node`) — is not in `for_each_child` at all, so
a slot's content is never visited either, expanded or not.

The second one was reachable from a guest, and this document used to say that
`<x:card><div @dangerouslysetinnerhtml=".payload"></div></x:card>` passed
`check_view` with no refusal. It does not: both walks `check_view` runs —
`@sanitize.Sanitizer::visit` (`anode/sanitize/sanitize.mbt`) and
`visit_untrusted_view` (`policy/view_authority.mbt`) — descend `MacroData.slots`
explicitly, and each has a test standing on that (`policy_test.mbt`,
"untrusted network checks reach macro slots"). What is still true is the
sentence about `for_each_child`, which is a walk over *structural* children and
visits an expanded call's body once rather than its slots twice — the reason
both `has_raw_html` and `collect_classes` document "call on COMPILED views", and
the reason neither is what a policy decision stands on.

**The half of a macro call that nothing was looking at: the arguments.** A
macro's body is the HOST's text and is deliberately not visited — a host that
registered a macro vouched for what is in it. Its arguments are the guest's
(`MacroData.attrs`, the caller's strings, substituted wherever `^name` appears
in that body), and no walk read them. A host macro whose body places `^icon` in
an `<img src>` therefore handed an untrusted guest the sink the same guest is
refused by name two lines away.

`visit_untrusted_view` now judges each argument for the worst position it could
land in: a sink, so a URL in it is a request the guest chose, and a `class`, so
brackets in it are guest-authored CSS. Arguments arrive as value SOURCE
(`Attrs::to_macro_vars` stringifies the parsed `Val`), so `macro_arg_text`
reads back the two shapes that state text — a quoted constant and the literal
head of a `$'…{…}'` template — and judges those.

The residual is stated rather than papered over: an argument that is an
EXPRESSION (`.avatar`, `$url`) has no text until it renders, so a host macro
that pipes a parameter into a URL sink still extends that sink to whoever can
call it. That is authority the host granted by writing the macro, and the fix
for it is the macro, not this walk.

**The port landed** — the [WHATWG Sanitizer
API](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#sanitizer)
config model over the compiled tree (`anode/sanitize`): `elements` /
`removeElements` / `replaceWithChildrenElements` / `attributes` /
`removeAttributes` / `comments` / `dataAttributes`, with per-element attribute
rules on the `elements` entries (the spec's
`SanitizerElementNamespaceWithAttributes`; `removeElements` and
`replaceWithChildrenElements` entries carry none). The design is
[`docs/sanitizer.md`](../docs/sanitizer.md).

Following the spec's shape rather than inventing an allowlist means the default
is the one the platform already argues is safe, and the same config can later be
handed to the native `Element.setHTML()`.

**A second finding, from doing that properly: an SVG `<script>` was not
refused.** The baseline list was written from a summary of the spec rather than
from the spec, and the spec lists `script` TWICE — once per namespace. Element
identity here is namespace-qualified, so `html("script")` never matched, and

```html
<div><svg><script>alert(1)</script></svg></div>
```

passed `check_view` with no violation at all: registered, rendered into the
host's page, and an SVG `script` inserted through the DOM executes. Unlike the
macro-slot hole above this was **unconditional** — it needed nothing from the
host. `svg("script")` is in `unsafe_elements` now, and the list is held against
the spec's own machine-readable baseline by a test rather than against anyone's
reading of it (`scripts/fetch-sanitizer-defaults.mjs`).

**But the Sanitizer API does not answer the URL-scheme question, and an earlier
version of this section said it did.** URL schemes are out of scope for that
spec: its unsafe baseline is about script-bearing ELEMENTS (HTML `embed`,
`frame`, `iframe`, `object`, `script`, and SVG `script` and `use`) and event-handler ATTRIBUTES, and its
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

**An untrusted dyncomp has a stricter rule than an ordinary app view.** URL
scheme filtering prevents script URLs, but it does not prevent a guest from
using `<img src>`, `<a href>`, `<form action>`, SVG `fill="url(...)"`, inline
CSS, or a utility such as `bg-[url(...)]` as a network egress channel. Nor can
registration validate the value of `:src=".field"`, because that value does
not exist yet.

`Policy::check_view` therefore refuses the sink **name**, at registration, for
the `Untrusted` tier (`policy/view_authority.mbt`): navigation/subresource URL
attributes, inline and SVG CSS URL sinks, `<style>`, `<link>`, `<meta>`, SMIL
elements that can mutate a sink after filtering, runtime HTML/Markdown, and
bracketed arbitrary utility classes. Literal host-provided utility names such as
`flex gap-2` remain available. `Granted` and `System` retain the normal
render-time URL scheme filter and the richer view surface.

This intentionally means an untrusted component cannot even render a relative
link or image directly. There is no value-level distinction between “a useful
fetch” and “an exfiltration fetch” that the guest cannot choose dynamically —
so the decision a host CAN make is not about the value, it is about the origin.

**`cap-external-urls`: the origin is the host's decision, written in the view.**
The rule above says a component that needs a picture "asks the host through a
deliberately authorized channel". This is that channel, and it is a capability
like the others: requested by the static manifest, granted per host, and
refusing the bundle when it is not granted rather than degrading it.

```moonbit
// The list and the grant are one call, because they are one decision.
@policy.Policy::untrusted().allowing_external_urls(["https://cdn.bsky.app"])
```

What it reopens is exactly two attributes — `src` on `<img>`, `href` on `<a>`
(`external_url_attr`) — and what it charges for them is that the ORIGIN is a
literal in the view:

- `<img src="https://cdn.bsky.app/img/avatar/plain/x@jpeg">` — a constant.
- `<img :src="$'https://cdn.bsky.app/img/avatar/plain/{.did}/{.cid}@jpeg'">` —
  literal through the `/` that ends the authority, dynamic from there.
- `<img :src="$'{$$mediaOrigin}{.avatarPath}'">` — a CONFIG variable the host
  bound (§3a). Still a literal when the host looks at it; the host is just the
  one who wrote it.
- `<img :src=".avatar">` — refused. The origin is a value, so nothing about
  where this points was settled when the host looked at it.

That is decidable at registration for the same reason the sink-name rule is:
the leading run of a `StrTpl`'s parts is literal or it is not, and a URL whose
authority is already closed by a `/` cannot be re-pointed by anything
interpolated after it (`policy/external_url.mbt`). `origin_of` refuses
userinfo outright —
`https://cdn.example@attacker.test/` is `attacker.test` to a browser and
`cdn.example` to a prefix comparison — and refuses a backslash, a control
character or a space in the authority, where the browser's own normalization
would move the boundary after the check.

The honest limits, in the order they matter:

- **It is a network grant.** An image the guest chooses is a GET the guest
  chose, and the path is still the guest's to write, so an allowed origin is an
  origin that can be told things. Naming the origins is what turns "this bundle
  can talk to anyone" into "this bundle can talk to the CDN its pictures are
  on"; an empty list means any `https://` origin and should be justified before
  it is used.
- **A path in an entry is dropped, not honored.** `https://cdn.example/public/`
  is not a boundary — `/public/../private/key` is a URL to `/private/key` — so
  an entry normalizes to its origin rather than pretending to be narrower.
- **A relative URL stays refused with the capability granted**, which is not an
  oversight: `/logout` is a request to the HOST's origin carrying the host's
  cookies, and that is a different grant from "may load pictures from a CDN".
- **`<a href>` navigates.** A link the guest wrote is a link a person can click
  to an origin the host allowed; `target`/`rel` are the page's own concern and
  this capability says nothing about them.
- Everything else on the sink list stays refused with it granted — `<iframe
  src>` is a document with its own script, `<form action>` sends what a person
  typed, `srcset` is a list with a parser in it, and the CSS sinks are a
  stylesheet's worth of surface behind one attribute. A host that wants those
  wants a tier, not a capability.

`Granted` and `System` list the capability too, so a bundle that declares it is
not refused by the host that trusts it most; above `Untrusted` the whole URL
surface is theirs anyway and the check returns early.

The GATE is the registration check, not the manifest — same split as §2, where
the module's import section is the gate and the declared capability is what a
consent dialog can show. A bundle that declares `cap-external-urls` at a host
that does not grant it is refused whole (`check_capabilities`), which is the
right answer for a component whose pictures are the point. A bundle that uses
`<img src>` without declaring it is decided by the same rule as one that did:
the host either grants those origins to bundles it loads or it does not, and a
declaration cannot widen that.

`guests/bluesky` and `guests/slack` are the worked example on the guest side:
five origins between them, each a literal in a view, each paired with a path the
guest computes and nothing more, and an initials disc drawn UNDER every avatar
so a refused, missing or failed picture lands somewhere. `@shell.sample_policy`
is the matching host half, and it is a list rather than the empty one for the
reason above.

### 3a. Config vars: the origin can be a literal the HOST wrote

A view that names its origin as a literal is a view that only works at one
server. `guests/mastodon` was that: `https://files.mastodon.social/` in nine
sinks and again as a constant in the wasm, so pointing it at hachyderm.io meant
editing two files that had to agree, and getting one of them wrong produced a
timeline with no pictures and no error.

A **config var** closes that without moving the boundary. A manifest DECLARES a
variable — name, type, default, and a sentence saying what it is for — and a
host BINDS it (`@policy.with_config`). In a view, `$$name` resolves at PARSE
time to the bound literal, so `external_url_refusal` sees an ordinary pinned
origin and the rule above runs unchanged (`policy/config.mbt`,
`tscript/parse.mbt`).

```moonbit
// Binding an origin IS granting it — one call, one decision, like the list.
@policy.Policy::untrusted().with_config([
  ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
  ("instanceName", @policy.text("hachyderm.io")),
])
```

The invariant is not weakened by this; it is tightened. Before: *the origin is
a literal the guest wrote and the host allowed.* After: *the origin is a
literal the host wrote.* Both are settled before anything renders.

Four things hold it there, and each is load-bearing:

- **A manifest default is not a grant.** An unbound `origin` reaches the GUEST
  — so a bundle nobody configured is still what its author shipped — and never
  reaches a view. Otherwise a bundle would grant itself an origin by writing
  one in its own file, which would make the whole rule decorative. A host that
  ships the bundles it loads opts in explicitly with
  `trusting_manifest_config`, and that call is named for what it costs.
- **The type is stated twice, by both parties, and a disagreement refuses the
  bundle.** Without the host's half, a manifest could declare `type: "origin"`
  for a variable a host bound as prose — an internal API base, say — and turn a
  string the host meant as data into a network grant.
- **Only an `origin` reaches a view.** `Policy::view_config` hands the parser
  the origin-typed entries and nothing else, because `$$name` becomes a `Const`
  the URL rule will happily pin, so a `text` variable a view could name would
  be a `text` variable that could be an origin.
- **Both parses get the same table.** `register_bundle` parses each view twice
  — once into the tree that renders, once into a throwaway tree the policy
  screens — and they must resolve `$$name` identically or the check is about a
  document nobody displays.

The sharp edge, stated plainly: **binding an origin is granting it.** A host
that binds one from input it did not write — a query parameter, a model's
output — has granted whatever that input named. `origin_of` still refuses
anything that is not a well-formed http(s) authority, so the worst case is a
picture fetched from a server the input chose; that is not a way past the rule,
but it is a real decision and it belongs in host code that means it.

`guests/mastodon` is the worked example: two origins and one prose name, no
literal host anywhere in the bundle, and one build that reads any instance
there is.

**Custom elements are not banned, but they cannot be made an isolation
boundary.** Autonomous tags such as `<x-picker :items=".items">` and ordinary
scalar/structured properties remain allowed. The `is` attribute is refused for
untrusted views, closing customized built-ins, and the browser-native
URL/style/event surfaces above are removed. This preserves the useful custom
element binding that `AttrValue::Data` exists for.

The residual is explicit: constructing an autonomous custom element, or
assigning any of its properties, invokes JavaScript registered by the host
page. That constructor/setter can fetch, navigate, mutate global state or do
anything else the page can do. No attribute filter can distinguish an inert
`items` setter from a malicious `items` setter. A host loading hostile bundles
must therefore treat its registered custom-element implementations as trusted
gadgets and, where that is too broad, tighten `Policy::with_sanitizer` to an
element/attribute allow-list. Supporting arbitrary custom elements and claiming
they cannot execute host code are incompatible requirements.

**Every tutuca app installs one, not only a page that hosts bundles.**
`App::new` installs `@filter.Baseline` — the URL rule and the handler rule in
one traversal — and there is **no opt-out**: `App::set_sanitizer` re-aims the
chain and `App::add_filter` adds to it, neither removes it. Not tier-dependent
either, because there is no legitimate `javascript:` URL in a described view at
any tier. (Until 0.21 `set_filter(None)` did remove it; `docs/sanitizer.md`,
"What a host may change, and what it may only narrow", has why that went.)

**The rule used to have a hole where the value was not a string, and the shape
of that hole is worth keeping.** A view attribute whose value evaluates to a
list or a map becomes `AttrValue::Data(Json)` (`render/values.mbt`) — the shape
that makes `:items=".products"` assign a real object to a custom element.
`UrlFilter` skipped `Data` because a structured value is not a URL string, and
`set_prop` routed `Data` to property assignment BEFORE consulting
`never_assign`, the list that contains `href` for exactly this reason. The
browser then closes the loop: `node.href = <array>` runs the array through the
IDL setter's ToString, and `["javascript:alert(1)"]` stringifies to
`javascript:alert(1)`. An untrusted bundle needed only a `list<string>` field
and `<a :href=".links">`.

Each layer was locally reasonable and the composition was not, which is the
failure mode this document exists to catch. The skip was true about the MoonBit
value and false about the browser's coercion of it; the routing shortcut
optimized for a case (`Data` is a property by definition) whose exceptions it
then inherited. Both are fixed independently — the filter drops a structured
value on a URL attribute on shape alone, and `Data` no longer skips
`never_assign` — because a two-layer defense whose layers share an assumption
is one layer.

It also outlived the tests because the tests read serialized HTML. The live
vector on `<form action>` sets a property and leaves no attribute, so
`to_html().contains("javascript:")` was blind to it by construction. The
regressions assert on the property map.

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

**Raw markup is refused by default, and a trusted host can grant it.**
`vdom/filter/markup` sanitizes a payload against the same `SanitizerConfig` and
hands back described NODES — never a string, because a sanitized string that the
browser parses a second time is the mutation-XSS vector that has bitten every
sanitizer which shipped that shape.

What used to be missing was a way for `Policy::check_view` to know that a host
had installed that filter: a policy saying `raw_markup: true` beside an app
mounted without it would send the payload straight to `set_inner_html`
unchecked. So the permission and the filter are now derived from the SAME value.
`Policy` carries a `Sanitizer`; `Policy::with_sanitizer(config)` replaces it;
and `@markdown.filter_for(sanitizer)` returns the filter that sanitizer
requires — the markup filter in front of `Baseline` when raw markup is
permitted, `Baseline` alone when it is not. `set_app` hands the app the policy's
sanitizer (`App::set_sanitizer`), which is what calls it, so a host cannot hold
the permission without the filter and cannot take the filter away afterwards.

It is a function rather than a type-level proof because `dyncomp/policy` is a
leaf over `anode` and must not import `vdom` — the permission cannot carry
evidence about a filter without inverting that. What is available is to make one
function the only place the two are named together, and to test it from both
sides (`vdom/filter/markdown/install_test.mbt`).

Every tier's default sanitizer refuses raw markup. `Granted` and `System` can
opt into the paired sanitizer/filter deliberately. `Untrusted` cannot: even
after scripts and dangerous schemes are removed, dynamic HTML can still create
an ordinary network request and bypass the registration-time sink-name walk.

**The safe markup directives are refused for the same reason, and only for
it.** `@setinnermd`, `@setinnerhtml` and `@setinnersvg` need no permission
anywhere else in the framework — their payloads reach the DOM only through a
builder that asks the sanitizer about every element and every attribute value,
and `set_prop` fails closed on all three, so Pass 1 has nothing to refuse
(`docs/sanitizer.md`). This tier is asking a narrower question than XSS. An
`<img src>` the sanitizer is perfectly happy with is still a GET to an origin
the guest chose, issued from the host's page, and a runtime payload can
synthesize every sink `untrusted_sink_attr` refuses by name. So all three are
refused at `Untrusted` and unconstrained above it — which is the mirror image
of `@dangerouslysetinnerhtml`, refused everywhere by default and openable above
`Untrusted` with a permission.

**A third finding, from giving SVG a directive of its own: SMIL was not
refused by the baseline.** `<animate>`, `<animateMotion>`, `<animateTransform>`
and `<set>` are in `untrusted_sink_element` and were nowhere else. They assign
the attribute named by `attributeName` in the browser, *after* `check_view` has
read the tree and after the render-time filter has read the built nodes, so
`<a><animate attributeName="href" to="javascript:…"/></a>` presents both passes
with an `href` that is not the one that will navigate. A dyncomp guest was
covered; a plain app has no Pass 1 at all and reached the same markup through
`@setinnermd`'s HTML blocks. All four are in `unsafe_elements` now, alongside
`svg("script")` and for the same class of reason: there is no value to inspect
and no later point to inspect it at, so the element is the only thing left to
refuse.

**A fourth, in the other direction — a spelling nothing but the parser knew.**
`moonbit-community/html` implements WHATWG 13.2.6.4 "adjust foreign
attributes", which splits a qualified name and returns it space-separated:
`xlink:href` in a payload arrives as `xlink href`. Every rule in the tree knows
the colon form, because that is the only spelling a *view* can write —
`@filter.url_attrs`, and `untrusted_sink_attr` in this package's own
`view_authority.mbt`. So `<a xlink:href="javascript:…">` inside a raw-markup
payload went past the URL rule untouched. It would then have reached
`set_attribute("xlink href", …)`, which throws on the space, so this was a
latent hole rather than a live one — but relying on that is relying on an
accident of the DOM API, which this document has already been wrong to do once
(see the `onclick` routing note in `docs/sanitizer.md`). `foreign_attr_name` in
`vdom/filter/markup/nodes.mbt` folds the name back before any rule reads it.

## 4. Guest CSS: no global stylesheet, a value validator, and a stylesheet one to come

**The finding, and a correction.** A guest's static manifest `style` rides on the
`"main"` **view's** style, not on `common_style` (`host/bundle.mbt`), and
`Component::compile_style` emits it as
`[data-cid="N"][data-vid="main"]{<style>}` by string concatenation
(`component/component.mbt`). A `style` of `} html { … } .x {` closes the wrapper
and applies globally.

`global_style` — emitted verbatim and unscoped by the same function — is **not
reachable by a guest**: `Component::for_type` defaults it to `""` and
`register_bundle` never passes it.

**What is true now.** Two things.

No global CSS for guests, as an invariant of the bundle format:
the v0.6 static manifest has no field that reaches `global_style`. Unscoped CSS from a bundle would
reach the page around it, and no amount of validation makes that safe.

And an **untrusted bundle ships no CSS at all** — `Policy::check_style` refuses
a non-empty `style` at the default tier, on the grounds that a bundle should
style with the host's utility classes, which the host compiles and which
therefore cannot break out of anything. All three sample guests already do
exactly that, so the strict default costs nothing real.

That includes CSS smuggled through view syntax as a bracketed arbitrary utility
class. Those are still refused by substring test (`has_arbitrary_css`).

**Inline CSS is no longer refused by name.** An untrusted view may STATE a
constant `style` or SVG presentation attribute, and it is read:
`anode/sanitize/css` parses the declaration list against
`CssPolicy::payload()` and **re-emits it**, so `fill="#1da1f2"` and
`style="display:flex;gap:4px"` reach the page and a fetch, an overlay, an
`!important` or a `<style>` block does not. A DYNAMIC value in one of those names
stays refused, and that is not caution: `check_view` runs at registration, the
host installs `@filter.Baseline`, which carries no CSS rule, so nothing
downstream would ever look at what this pass cannot see.

The design, the subsets and the two findings behind them are in
`docs/css-validator.md`. The one worth repeating here is that the value is
**re-emitted rather than approved**, so a declaration list that survives contains
no byte the validator did not choose — which is what makes "the guest wrote it"
stop mattering.

The generated property table also settled a question this section could not have
answered by hand. `untrusted_sink_attr` names fourteen CSS sinks; the
specifications name thirty-three, and `background` — the shorthand containing the
`background-image` that IS on the list — was one of the misses.

**What is still unvalidated is the scoped `style` BLOCK.** Above the untrusted
tier `Policy::check_style` accepts it whole, and `Component::compile_style` still
pastes it into `[data-cid="N"][data-vid="main"]{…}` by string concatenation, so a
`}` escapes the wrapper. `allow_custom_css` still means someone vouched for the
bundle, not that anything checked it.

What would close it: parse the block as a rule list, keep `@media`/`@supports`/
`@keyframes`, refuse `@import` and `@font-face`, validate each declaration with
the validator that now exists, and **prefix each selector with the scope** rather
than wrapping the block — which is what structurally kills the brace-breakout.

The one thing in the way is escapes. The value validator refuses a backslash
outright, because `mizchi/css/token` does not decode them and there is no sound
name comparison over its output otherwise; a SELECTOR cannot take that deal,
since Tailwind emits `.bg-\[\#fff\]`. So the stylesheet half needs either a fix
upstream in `mizchi/css` — its `consume_name` not implementing css-syntax-3
§4.3.7 is a real bug worth sending back — or a tokenizer of our own.

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

The archive layer is bounded before manifest quotas can apply: 16 MiB
compressed, 64 MiB expanded, 32 MiB per tar entry, and 8192 files. These are
availability ceilings rather than permissions and live in `ARCHIVE_LIMITS` so
the loader and its regression tests share one definition.

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
anything it says about itself. The static manifest's `doc` / `version` /
`homepage` / `authors` are advisory; nothing resolves against them.
Content-addressed bundle ids (SHA-256, computed in the JS loader) are the
next step, and signing is a step after that.

## What to check when changing this

- Adding a field to the static manifest: does anything you added reach
  `global_style`, resolve an external resource, or reach the DOM as text rather
  than as a description? Those are the shapes that have gone wrong here.
- Adding an element, attribute, directive or class compiler feature: can it
  fetch directly, accept CSS `url()`, mutate another attribute after filters,
  or invoke a host custom-element setter? Update the untrusted authority walk
  and its macro-slot tests if so.
- Adding a way for a guest to hand the host a string that ends up in markup —
  a macro argument was one, and had nothing reading it for four releases. Ask
  where the string can LAND, not what it is called at the call site.
- Widening `cap-external-urls`: every attribute added to `external_url_attr`
  has to survive the question the two on it already answered — can the
  registration-time check see the whole origin, and is what the attribute does
  with that origin a fetch rather than a document, a form or a stylesheet?
- Adding a WIT export: is it runtime behavior that genuinely cannot be static
  bundle data? Metadata in wasm executes code merely to describe code and
  expands the canonical ABI attack surface.
- Adding to `control`: is it buffered and applied by the host, or does it act?
  Only `log` acts, and only because logging cannot be misused into anything.
- Adding to `env`: is the answer weaker than the platform's own, and is it
  frozen or seeded so a dispatch still replays?
