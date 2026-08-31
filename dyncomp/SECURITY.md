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
| wasm imports (`values`, `control`, `config`) | nothing ambient | **safe by construction** — the world has no clock, no entropy and no timer; anything a guest cannot compute it asks the host for over an intent (§2) |
| guest views (tutuca templates) | the host's DOM/network | **handled for untrusted bundles** — unsafe names, direct network sinks, raw markup/Markdown, guest-authored arbitrary utility CSS and URL-bearing macro arguments are refused; a CONSTANT inline `style` or SVG presentation attribute is parsed and re-emitted rather than refused (§4), while a dynamic one stays refused; `<img src>`/`<a href>` reopen only when the host allows external URLs, and only to an origin settled before render — a literal the view states, or a config var the HOST bound (§3a); autonomous custom elements remain a host-code trust boundary |
| guest CSS (static manifest `style`) | the host's stylesheet | **partly handled** — refused outright for an untrusted bundle; unvalidated above that. The declaration half now has a validator (§4); the selector and at-rule half does not |
| `control.intent` → host handlers | the host's own services | **open** — needs caller-aware authorization; `IntentCall.from` is the plumbing that closes it, and no host uses it yet (§5) |
| public property setter | the component's own state tree | **contained** — synchronous pure COW transition; manifest type/writable checks, guest refusal, successor-domain validation, and no `control` effects (§5b) |
| guest view event paths (`e.<path>`) | the host's DOM, and through it the page | **handled** — every step through a host object is checked against a curated allow-list, not just the first one (§9) |
| a hung or runaway guest call | the page's responsiveness | **open** — needs worker isolation |

The decisions live in [`policy/`](policy/) and are enforced by
`register_bundle` before it parses anything; `policy/policy_test.mbt` is the
executable form of most of this document.

## 1. The wasm sandbox

`world dynamic-component` imports three callable interfaces (`values`,
`control`, `config`) plus the types-only `tables` interface, and no WASI
(`wit/tutuca-component.wit`). A guest therefore has **no** filesystem, network,
sockets, environment variables, subprocesses, storage, clock or entropy. It
cannot reach the DOM at all: tutuca has no element event handlers, so a view
is a description rather than a place to put code, and the guest renders
nothing.

That is stronger than the usual "it's sandboxed, it's wasm". Several specific
properties follow from the contract's shape rather than from the wasm engine:

- **Control calls are buffered, not performed.** Everything in `control` except
  `log` is collected during `handle-message` / `handle-intent` and applied by the HOST afterwards,
  through the dispatching `&Ctx` (`host/dynobj.mbt`, `obj_handler`). The guest
  does not act; it asks, and the host chooses.
- **Paths are relative only.** `send-at` / `intent-at` address the dispatching
  instance's own subtree. Absolute paths are deliberately absent from the WIT,
  so a component cannot address the tree it happens to be mounted in.
- **`make-instance` is same-bundle only**, in the host-assigned token space.
- **Arena handles die at the call boundary**, so nothing a guest captured stays
  reachable after it returns.
- **The static manifest's type table is depth-guarded** at 16 (`host/manifest.mbt`,
  `ty_info_at`), because a manifest that crossed a trust boundary cannot be
  trusted to be acyclic.
- **No clock means no measurement.** A guest cannot read time at all, which
  removes the primitive most timing side channels are built from.

## 2. No ambient facts: a guest asks, over an intent

Components genuinely need "what time is it" and "give me an unpredictable
number", and the world deliberately gives them no way to take either. There is
no `wasi:clocks` + `wasi:random`, and no host-supplied `env` interface either,
for three reasons in order of weight:

1. The world imports no WASI, and adding it drags preview2 shims into the
   browser that nothing else needs.
2. A real monotonic clock is exactly the primitive a timing side channel is
   built from.
3. An ambient clock makes a dispatch unreplayable, which contradicts the first
   principle of this design — *the host is the framework*.

What a guest cannot compute it ASKS for, through `control.intent`, and that is
a different kind of thing from ambient authority: the host answers one
question, once, per call, from a handler it registered by name — and it can
decline. `examples/dyncomp-dice` is the worked example: the die cannot make
the one number it exists to produce, so it dispatches a `roll` intent and the
page's `IntentFn` answers with the page's own entropy
(`dyncomp/shell/shell.mbt`, `sample_host_intents`). The host is not lending
the guest a generator; it is answering a question, and every answer flows
through the same dispatch path as every other message — recorded, replayable,
and visible to the page that gave it.

This is why there is no capability vocabulary here any more. A capability was
an import the manifest requested and the host granted ahead of time; an intent
is a question the host answers at call time, with the caller's path on the
call (`IntentCall.from`, §5) if it wants to discriminate. The second shape
subsumes the first and keeps the world's import section closed: for v0.6
descriptor bundles, the host-owned ABI checks the core module's actual import
section against the contract before the first guest instruction runs, and
anything outside `values`/`control`/`config` refuses the bundle.

The external-URL question (§3) is the one piece of the old vocabulary that
survives, as a policy field rather than a grant: it was never about an import
— it is about what a guest's VIEW may name, checked at registration.

A browser host chooses its policy through `@uiw.mount(policy=…)`, or
`@dhw.set_app(…, policy~)` for a page that does its own mounting; `set_policy`
changes it afterwards, for a host that asks a person first. It applies at
LOAD, so narrowing it does not retract a bundle already registered — revoking
is dropping the bundle.

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

**Where the refusal is weaker than it sounds.** `has_raw_html`
(`anode/classes.mbt`) walks `ANode::for_each_child`, and that walk has two blind
spots on an unexpanded tree. A `MacroCall`'s `node` is `None` until
`ParseContext::compile` expands it, so a macro BODY is never visited; and
`MacroData.slots` — the caller's own subtrees, keyed by slot name
(`parse_context.mbt`, `new_macro_node`) — is not in `for_each_child` at all, so
a slot's content is never visited either, expanded or not.

`<x:card><div @dangerouslysetinnerhtml=".payload"></div></x:card>` does not
pass `check_view`: both walks `check_view` runs —
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

**The external-URL allowance: the origin is the host's decision, written in
the view.** The rule above says a component that needs a picture "asks the
host through a deliberately authorized channel". This is that channel, and it
is entirely the host's: a policy field (`allows_external_urls`) plus the list
of origins, set together, with nothing for a manifest to declare.

```moonbit
// The list and the allowance are one call, because they are one decision.
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

- **It is a network allowance.** An image the guest chooses is a GET the guest
  chose, and the path is still the guest's to write, so an allowed origin is an
  origin that can be told things. Naming the origins is what turns "this bundle
  can talk to anyone" into "this bundle can talk to the CDN its pictures are
  on"; an empty list means any `https://` origin and should be justified before
  it is used.
- **A path in an entry is dropped, not honored.** `https://cdn.example/public/`
  is not a boundary — `/public/../private/key` is a URL to `/private/key` — so
  an entry normalizes to its origin rather than pretending to be narrower.
- **A relative URL stays refused with the allowance in place**, which is not an
  oversight: `/logout` is a request to the HOST's origin carrying the host's
  cookies, and that is a different decision from "may load pictures from a CDN".
- **`<a href>` navigates.** A link the guest wrote is a link a person can click
  to an origin the host allowed; `target`/`rel` are the page's own concern and
  this allowance says nothing about them.
- Everything else on the sink list stays refused with it in place — `<iframe
  src>` is a document with its own script, `<form action>` sends what a person
  typed, `srcset` is a list with a parser in it, and the CSS sinks are a
  stylesheet's worth of surface behind one attribute. A host that wants those
  wants a tier, not an allowance.

Above `Untrusted` the whole URL surface is a bundle's anyway and the check
returns early, so the flag is inert there and the tier constructors leave it
false.

The GATE is the registration check, not anything a bundle says about itself —
same split as §2, where the module's import section is the gate. The host
either allows those origins to bundles it loads or it does not, and nothing a
bundle ships can widen that.

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
// Binding an origin IS allowing it — one call, one decision, like the list.
@policy.Policy::untrusted().with_config([
  ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
  ("instanceName", @policy.text("hachyderm.io")),
])
```

The invariant is not weakened by this; it is tightened. Before: *the origin is
a literal the guest wrote and the host allowed.* After: *the origin is a
literal the host wrote.* Both are settled before anything renders.

Four things hold it there, and each is load-bearing:

- **A manifest default is not an allowance.** An unbound `origin` reaches the
  GUEST — so a bundle nobody configured is still what its author shipped — and
  never reaches a view. Otherwise a bundle would allow itself an origin by
  writing one in its own file, which would make the whole rule decorative. A
  host that ships the bundles it loads opts in explicitly with
  `trusting_manifest_config`, and that call is named for what it costs.
- **The type is stated twice, by both parties, and a disagreement refuses the
  bundle.** Without the host's half, a manifest could declare `type: "origin"`
  for a variable a host bound as prose — an internal API base, say — and turn a
  string the host meant as data into a network allowance.
- **Only an `origin` reaches a view.** `Policy::view_config` hands the parser
  the origin-typed entries and nothing else, because `$$name` becomes a `Const`
  the URL rule will happily pin, so a `text` variable a view could name would
  be a `text` variable that could be an origin.
- **Both parses get the same table.** `register_bundle` parses each view twice
  — once into the tree that renders, once into a throwaway tree the policy
  screens — and they must resolve `$$name` identically or the check is about a
  document nobody displays.

The sharp edge, stated plainly: **binding an origin is allowing it.** A host
that binds one from input it did not write — a query parameter, a model's
output — has allowed whatever that input named. `origin_of` still refuses
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
any tier.

**The value that is not a string is where URL rules go to die.** A view
attribute whose value evaluates to
a list or a map becomes `AttrValue::Data(Json)` (`render/values.mbt`) — the shape
that makes `:items=".products"` assign a real object to a custom element.
A URL filter that skips `Data` "because a structured value is not a URL string",
combined with `set_prop` routing `Data` to property assignment before consulting
`never_assign`, closes a loop in the browser: `node.href = <array>` runs the
array through the IDL setter's ToString, and `["javascript:alert(1)"]`
stringifies to `javascript:alert(1)`. An untrusted bundle needs only a
`list<string>` field and `<a :href=".links">`.

Each layer is locally reasonable and the composition need not be, which is the
failure mode this document exists to catch. The filter therefore drops a
structured value on a URL attribute on shape alone, and `Data` does not skip
`never_assign` — because a two-layer defense whose layers share an assumption
is one layer.

These vectors also leave no attribute behind — on `<form action>` the live one
sets a property — so a test asserting on serialized HTML
(`to_html().contains("javascript:")`) is blind to them by construction. The
regressions assert on the property map.

This glue does not install a filter of its own: two filters would mean reports
split across two logs, and the app's own is installed before `set_app` is ever
called. What stays here is `take_filter_reports()`, which drains the app's — by
render time there is no author to tell, so a page that wants to say "this
component tried to render a `javascript:` URL" reads it from there.

**Raw markup is refused by default, and a trusted host can grant it.**
`vdom/filter/markup` sanitizes a payload against the same `SanitizerConfig` and
hands back described NODES — never a string, because a sanitized string that the
browser parses a second time is the mutation-XSS vector that has bitten every
sanitizer which shipped that shape.

The permission and the filter derive from the SAME value — without that
coupling, a policy saying `raw_markup: true` beside an app mounted without the
filter would send the payload straight to `set_inner_html`
unchecked. `Policy` carries a `Sanitizer`; `Policy::with_sanitizer(config)`
replaces it;
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

## 5. `control.intent`: a bundle's own handlers are fine, the host's are not

An intent on the `lex` leg resolves against the bundle's own handlers first,
then the host's: `register_bundle` puts the bundle's in a child scope and
`lookup_intent` walks child → parent.

**A bundle's own handlers need no policy.** They run inside the guest, which
has no authority of its own, so they inherit exactly the same limitation as
every other line of guest code. Nothing to add.

**Host-registered handlers are the open one.** A guest can call any of
them with any arguments. In `demo/universal_wasm` those are `double`,
`listComponents`, `makeComponent`; in a real app they are whatever the app's
services are — and after §2, they are also where a clock or entropy comes
from, which makes this seam the whole of what a guest can ask a page for.

The fix is not a manifest-declared allowlist — that would ask the untrusted
party what it is allowed to do. It is to authorize **at call time, from the
requester's path**, and let the host decide: the path already identifies the
caller, and a `DynObj` sitting at it names its bundle.

The plumbing supports that: `IntentFn` takes an
`@tutuca.IntentCall` (`core/path_spec.mbt`), which carries `name`, `args` and
**`from` — the sender's `DispatchPath`**. `Transactor::push_intent` fills it in
from the position the intent was dispatched at (`transactor/walk.mbt`), and a
`DynObj` sitting at that path names its bundle.

So the mechanism is here and the decision is the host's. What remains open is
that no host in this repository USES it yet: `demo/universal_wasm` still
registers `double` / `listComponents` / `makeComponent` for anyone who asks.

### 5a. `control.lookup`: a map the host filled, not a walk the guest takes

`lookup` is the one function on `control` that answers rather than acting, and
what makes it safe is that it does not reach anything while it runs.

`dynobj.mbt`'s `obj_handler` resolves this component's DECLARED lookups —
`DynComponentDef.lookup`, which came from the manifest — through the
dispatching `&Ctx` BEFORE the guest is entered, and passes the answers in as
`Guest::dispatch`'s `bindings`. `control.lookup(name)` reads that map. So:

- the set of names is fixed by the manifest, at registration, and a name the
  bundle did not declare is simply not there;
- the values are resolved at the guest's OWN position, along the default
  `[dyn, lex]` route, by the same `ctx.lookup` a host component uses — a
  binding published to a subtree this instance is not in was never resolved
  and is not in the map;
- there is no route parameter, so a guest cannot ask for a different walk than
  the one the host took, and the WIT says so rather than accepting one and
  ignoring it.

The reach is therefore exactly what the guest's own VIEWS already had: a view's
`*name` resolves against the same frames. What 0.10.0 added is a place to use
it from, not a place to reach.

### 5b. Public properties: state transition, not an effect channel

Manifest v3 declares properties separately from storage fields. A declaration
fixes a name, type, and visibility, and opts into writing explicitly; matching
an internal field name grants nothing. Only `public: true` admits host access.
The host checks all four before calling a setter.
It also validates the value returned by the successor's getter and evaluates
the successor against the manifest's field domains before adopting it
(`host/dynobj.mbt`, `obj_property` / `obj_set_property`). A refusal or malformed
successor is dropped and the old root remains intact.

The transition is synchronous, which is what lets a parent replace a nested
child in the same transaction instead of sending it a message and waiting for
a second one. It is nevertheless pure. Tutuca-generated complex setters reject
send/intent/new/effectful bodies in `tscript/check`; for a hand-written guest,
`host/wasm/loader.mjs` marks property calls as a pure phase and refuses every
buffered `control` operation plus child creation/destruction. `log` remains the
one immediate diagnostic operation, as everywhere else. The setter can compute
arbitrarily and can return a successor containing several internal field
changes, but nothing becomes visible until the host adopts that whole value.

This is not a new route through the component tree. A setter receives no
`Ctx`, path, sender, lookup bindings, or reply channel. Nested access is a host
copy-on-write walk over a path it already holds, and the guest sees only its own
property name and typed value.

## 6. Availability

Guest calls are synchronous, so an infinite loop or a runaway `memory.grow`
inside a handler, render operation, property accessor, or setter freezes the tab. This is an availability problem, not a
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
`localStorage` under a prefix the page chooses. A guest cannot reach it — the
contract has no storage call, and `persist` is a value the host asked for
rather than a call the guest makes. Two bundles cannot read each other's snapshots
through the contract; whoever hosts them decides what the store holds and what
is handed back.

## 8. Provenance

A bundle's identity should be the **hash of the archive it arrived in**, not
anything it says about itself. The static manifest's `doc` / `version` /
`homepage` / `authors` are advisory; nothing resolves against them.
Content-addressed bundle ids (SHA-256, computed in the JS loader) are the
next step, and signing is a step after that.

## 9. Guest view event paths: every step is checked, not just the root

A view is DATA the host compiles, and a dyncomp guest supplies its views as
data (`DESIGN.md`, principle 2). So anything a view template can reach is
authority the host granted by compiling it — and nothing on the other end
declared it, which is what principle 4 forbids.

An `@on` handler's arguments are where a view reaches the DOM. In v2 they are
written `e.<path>`, and two rules bound what a path can be.

**Rule 1: an `e.` path always produces a `Value`.** Never an element, never a
document, never a host object. A leaf that is not representable is `Null`, so
`e.target` on its own is `Null`.

**Rule 2: under the SAFE event-path profile, every step through a host object
is on an allow-list — not only the first.** This is the one that is easy to get
wrong, and an earlier draft of the design got it wrong: it allowlisted the ROOT
segment and let the path run free below it. One line shows why that does not
hold.

```
e.target.ownerDocument.defaultView.localStorage.length
```

`target` is a permitted root, every step after it is an ordinary property read,
and the leaf is a **number** — so it converts cleanly under rule 1, and a view
template has just read the window.

### The profile, and who runs which

The allow-list is one of two PROFILES (`@eventpath.EventPathProfile`). `Open`
lets any path resolve; it is what an app's own views run, because those are
their author's code and the author could have written the same read in JS — for
them the generator only reports an off-list step as an `EVENT_PATH_UNSAFE_STEP`
hint. `Safe` holds every traversed step to the list below, and **it is what
this host runs, in every tier**: views are data here whoever shipped them.
`Policy` carries the answer on `event_paths` (loosen deliberately with
`with_open_event_paths`), and it is enforced TWICE, by agreement:

1. **At registration.** `screen_view`'s shadow parse registers the view's
   events, and `Policy::check_event_paths` refuses the bundle over an off-list
   path, naming the step and its index — a guest whose component would have
   read `Null` on every dispatch never renders at all.
2. **At dispatch.** The bridge hands the same profile to its app
   (`set_app` → `App::set_event_paths`), so the runtime resolver answers
   `Null` past the allowlist even if some other path in — the second fence,
   not a second opinion.

### The list, and where it lives

`eventpath/event_paths.mbt` — `event_object_steps`, six entries:
`target`, `currentTarget`, `relatedTarget`, `detail`, `dataset`,
`dataTransfer`. `check_event_path` walks a path and refuses at the first
traversed step that is not one of them, naming the step and its index.

Beside it, `event_data_terminals` — `dataset` and `detail` — below which
traversal is **free**. That is not a weakening: a `DOMStringMap` is attributes
the author wrote into the template and a `CustomEvent.detail` is an object the
application constructed, so once a step reaches author data there is nothing
left to escalate into. The allow-list governs exactly the boundary between host
objects and data, and no further — which is also what keeps the language open,
since `e.detail.a.b.c` needs no framework release.

### Why this list is different from every other one here

**It cannot be generated.** The sanitizer baseline comes from the WHATWG spec's
own `builtins/` at a pinned commit; the DOM property table beside it comes from
`w3c/webref`'s extracted IDL at a pinned commit. A specification says what
EXISTS. None of them says what a view template should be allowed to reach,
because that is a judgment about authority rather than a fact about the
platform.

So it is argued, and being argued makes it the only list in the repository that
can grow by accident. `eventpath/event_paths_test.mbt` asserts the **exact** list,
so a seventh entry fails a test in a diff that names it, and walks six known
escape paths asserting each is refused at the right step.

### The second fence

`eventpath/dom_props_gen.mbt` deliberately carries no `Window` and no `Document`.
No allowlisted step lands on either, so a path through one has no typed
continuation — a second reason the `localStorage` line above is refused, after
this list's first. Two tests assert those absences, so neither can drift into
being an accident. (Under `Open` the fence is gone with the gate: an open host's
own views can read the window, which is the point of opening.)

### What a component does when it needs more

It **dispatches an intent** and the host answers. The two channels differ in
exactly the way that matters here: an event path has no caller to authorize —
a view is compiled data, so nothing is on the other end — while an intent
carries `IntentCall.from`, and a host holding that can decide. Authority is
extended through a channel that knows its caller, never reached through one
that does not, which is principle 4 applied to the DOM instead of to wasm
imports.

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
- Widening the external-URL allowance: every attribute added to
  `external_url_attr` has to survive the question the two on it already
  answered — can the registration-time check see the whole origin, and is what
  the attribute does with that origin a fetch rather than a document, a form
  or a stylesheet?
- Adding a WIT export: is it runtime behavior that genuinely cannot be static
  bundle data? Metadata in wasm executes code merely to describe code and
  expands the canonical ABI attack surface.
- **Changing the WIT is a whole-repository migration, not a compatibility
  exercise.** Bump the one world version; update `host/wasm/abi.mjs`, loader
  imports and MoonBit glue; regenerate every name in `guests/guests.mjs` from
  the one WIT; migrate the canonical SDK, all handwritten MoonBit and Rust
  guests, every linker export list, the card compiler/Wax runtime/CardGuest
  bridge, descriptor packers, manifest version/api/properties, the scaffold
  template embed, and the self-contained dyncomp-dice consumer. Run the core
  ABI/archive harnesses and `guest-harness`. Do not retain older import keys,
  export descriptors, adapters, optional manifest fields, or world fallbacks:
  a partial old bundle must be refused rather than half-work.
- Adding or widening a property setter: is it separately declared writable,
  type-checked before the call, type/domain-checked after it, atomic on
  refusal, and barred from every `control`/child effect at both the source and
  wasm boundaries? Public fuzzing should discover only `public: true`
  properties; field-operation tables remain internal implementation detail.
- Adding to `control`: is it buffered and applied by the host, or does it act?
  Only `log` acts, and only because logging cannot be misused into anything.
  v2's five — `intent`, `intent-at`, `forward`, `reply`, `fail` — are all
  buffered and all applied through the dispatching `&Ctx`, exactly as `emit`
  and `send` are, so a guest is not a special case on any of them.
  `send-reply` (0.10.0) is buffered like the rest, and reaches
  `ctx.send_reply`; with nobody waiting the HOST refuses `NO_SENDER` and
  nothing is dispatched, so a guest cannot address a component by replying to
  a message nobody sent.
- Adding a `control` function that ANSWERS: `lookup` (0.10.0) is the only one,
  and the shape is the whole of why it is safe. It does not reach anything
  during the call — the host resolves this component's DECLARED lookups before
  entering the guest and hands the answers in, so `lookup` is a map read over a
  set the manifest fixed. A name the manifest does not declare is not in the
  map. That means a guest cannot use it to walk the host tree, to probe for
  names, or to read a binding published to a subtree it is not in: the reach is
  what its own views already had, and the host chose it. Anything else that
  wants to answer should be built the same way, or it is a channel out of the
  sandbox rather than a value.
- Adding an ambient import (a clock, entropy, anything a guest reads rather
  than asks for): don't. The intent seam already carries it with the caller
  identified and the host deciding per call, and an ambient answer would have
  to be weaker than the platform's own AND frozen or seeded so a dispatch
  still replays — which is the intent answer with extra steps.
- **Adding a step to `event_object_steps`**: what does it reach, and can a path
  through it get out of the event and into the page? Ask it of the whole PATH
  and not of the step — `target` is fine and `target.ownerDocument` is the
  window two reads later. The exact-list test in `eventpath/event_paths_test.mbt`
  will fail; make the diff that changes it carry the argument, and add an
  escape-path case for whatever the new step's neighbours are. This is the one
  allow-list here that no specification can check for you.
- **Loosening `Policy.event_paths`** (or adding a tier constructor): views are
  data at every tier, which is why all three constructors default to `Safe`. A
  host that opens its page does so with `with_open_event_paths`, and the
  registration refusal (`check_event_paths`) and the runtime resolver
  (`set_app` → `App::set_event_paths`) read the SAME field — a change to one
  is a change to both by construction, which is what keeps them from
  disagreeing.
