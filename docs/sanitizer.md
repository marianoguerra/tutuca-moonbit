# Sanitizing an anode view

A design, not an implementation. It exists because `dyncomp/` compiles view text
it did not write into the host's own page, and because `dyncomp/SECURITY.md` §3
promises a port of the [WHATWG Sanitizer
API](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#sanitizer)
without saying what "port" means for a tree that is half description and half
expression. This says it.

## What the spec gives, and what it does not

The Sanitizer API is two things a caller can use separately:

- a **config model** — `elements` / `removeElements` /
  `replaceWithChildrenElements` / `attributes` / `removeAttributes` / `comments`
  / `dataAttributes`, with per-element attribute rules on the `elements` entries
  only, and a validity relation between them that is part of the spec rather
  than advice;
- an **entry-point split** — `setHTML()` always applies the unsafe-removal pass
  on top of whatever config you hand it, `setHTMLUnsafe()` honours the config
  verbatim. `Sanitizer.removeUnsafe()` is a third thing: a method that mutates a
  config, not the baseline itself.

What it does NOT give is any opinion about attribute *values*. Its unsafe
baseline is script-bearing elements (`script`, `iframe`, `object`, `embed`,
`frame`, `base`, `use`) and event-handler attributes; its own default
configuration allows `href` on `<a>`, and `<a href="javascript:…">` comes
through `setHTML()` untouched. The platform answers that half with CSP and
Trusted Types. anode has to answer it itself, and somewhere else.

So: **the config model ports, the baseline ports, the entry-point split does not
(there is no unsafe entry point worth having here), and URL schemes are a second
mechanism that shares nothing with the first.**

## Two passes, because half a view is known at compile time

Everything the config model asks about is a *name*. Every name in an ANode tree
is a literal. That is the whole reason this split is clean:

| Sanitizer concept | ANode carrier | Decidable at compile time |
|---|---|---|
| element name | `DomData.tag` | **yes** |
| element namespace | `DomData.ns : Ns?` | **yes**, but only three namespaces exist |
| attribute name | `ConstA(name~)`, `Plain(name~)`, `IfAttr.name` | **yes** — names are always literals |
| comments | `ANode::Comment` | **yes** |
| `data-*` | attribute-name prefix | **yes** |
| raw-markup construct | `AttrItem::RawHtml` | **yes** (already: `has_raw_html`) |
| attribute value | `Const(lit)`, else a `Val` expression | constant only |
| raw-markup payload | the `Val` inside `RawHtml` | **no** |
| URL scheme | an attribute value | constant only |

Attribute names deserve the emphasis. They cannot be computed: the parser
lowercases every name it reads and `AttrParser::parse` stores it as a `String`
(`anode/attrs.mbt`), with exactly one rewrite — `:viewbox` → `viewBox`. So there
is no `:onCl${x}ick`, and no way to reach an IDL property whose name is
camelCase. An allowlist over names is therefore *complete* over the described
part of a view, which is the property that makes a static pass worth having at
all.

## Pass 1 — the static pass, `anode/sanitize`

**Implemented.** A leaf package over `anode`. `dyncomp/policy` imports it for the
refusal; `lint` can import it later for an advisory; nothing imports them.

### The config

```moonbit
pub(all) struct SanitizerConfig {
  elements : Array[ElementRule]?
  remove_elements : Array[ElementName]?
  replace_with_children_elements : Array[ElementName]?
  attributes : Array[String]?
  remove_attributes : Array[String]?
  comments : Bool?
  data_attributes : Bool?
  raw_markup : Bool?          // NOT in the spec — see below
}

pub(all) struct ElementName { name : String; ns : ElemNs }   // Html | Svg | MathML
pub(all) struct ElementRule {
  elem : ElementName
  attributes : Array[String]?
  remove_attributes : Array[String]?
}
```

Every field is `Option`, and that is not laziness: the spec distinguishes an
absent `elements` (no allowlist — a *remove* configuration) from an empty one
(allow nothing). Collapsing the two into `[]` loses the distinction that decides
the whole pass.

`ElemNs` is a closed set mirroring anode's own (`DomData.ns : Ns?`, where `None`
is HTML) rather than the spec's namespace URI string, so a config cannot name a
namespace anode has nowhere to put. Attribute names carry no namespace at all,
because a view cannot express one — see "What the tree cannot express".

`raw_markup` is tutuca's one addition to the model. The spec has no field for it
because there is no `innerHTML` *attribute* for it to be about;
`@dangerouslysetinnerhtml` is the one construct in a view whose content is not
described, so it gets a field. Absent means denied, which is the refusal
`Policy::check_view` already implemented.

### Safety comes from the entry point, not the config

`Sanitizer` applies the unsafe baseline — the seven unsafe elements, and every
`on*` attribute — **before** consulting the config, and a config that names
`script` in `elements` still does not get `script`. That is the spec's own
`setHTML()` / `setHTMLUnsafe()` split, collapsed: there is only the safe entry
point here, and no reason to build the other one for a host rendering views it
did not write.

The event-handler half is a *predicate* (`on` + at least one character) rather
than the spec's enumeration. A prefix test is a superset of that list and cannot
fall behind it as the platform adds handlers, which for a remove rule is the safe
direction to be wrong in.

### Validity is part of the port

The spec's constraints are load-bearing and a port that skips them diverges from
anything later handed to a real `setHTML()`:

- `elements` xor `remove_elements`; `attributes` xor `remove_attributes`
- `replace_with_children_elements` disjoint from both element lists
- no duplicates in any list
- with a global `attributes`: an element rule may carry `attributes` or
  `remove_attributes` but not both; its `attributes` must not repeat the global
  ones; its `remove_attributes` may only name global ones
- with a global `remove_attributes`: neither element-level list may overlap it,
  and `data_attributes` must not be set at all
- when `data_attributes` is true, no list may name a `data-*` attribute

`SanitizerConfig::validate() -> Array[ConfigError]` runs once, at construction.
An invalid config is a programming error in the host, not a guest's problem, so
it fails loudly rather than degrading.

### The default is the baseline, not the spec's default configuration

Two different things share the word "default" in the spec, and conflating them
is a bug in both directions.

The **baseline** (`removeUnsafe()`) is the seven elements and the event
handlers. The **default configuration** is a large allow-list of elements with
per-element attributes, which *additionally* drops comments and `data-*`.
MDN is explicit that the second is not the first: "calling `removeUnsafe()`, or
passing a custom sanitizer to the safe sanitization method, only removes the
XSS-unsafe items. It does not remove the additional items, comments, and `data-*`
attributes."

`SanitizerConfig::default()` here is the empty config, so the sanitizer is the
baseline alone. **The spec's default allow-list is not transcribed**, and that is
a deliberate gap rather than an oversight: it has to come from the specification
text rather than a summary of it, because an allow-list that quietly lost an
entry is a component that mysteriously fails to render and one that quietly
gained an entry is a hole. A host that wants an allow-list supplies one today and
gets `validate()` to keep it honest.

Two consequences of picking the baseline, both of which cost a test to find:

- **`comments` defaults to kept.** A baseline that dropped them would refuse an
  ordinary commented guest view, and would refuse the `Comment` nodes
  `ANode::parse` synthesizes for its own error paths ("Error: InvalidTagName …",
  "bad macro: …") — turning a guest's typo into a refusal about something else.
- **`data_attributes: false` does not mean "removed".** It means "not
  automatically allowed", so under a *remove* configuration `data-*` survives
  like anything else unnamed. Not symmetric with `comments`, which is an explicit
  boolean either way. That is what the spec says, and the asymmetry is worth
  knowing before reading the code.

### The four names a config may not eat

Whenever a host *does* supply an allow-list, one carve-out is mandatory:
`data-eid` is pushed by `AttrParser::parse_event` (`anode/attrs.mbt`) and is how
a rendered element finds its handler list, and `data-cid` / `data-vid` /
`data-nid` are stamped by `set_data_attr` during compile. An allow-list that
never mentions them produces a component that renders and then responds to
nothing — the worst available failure, because it reads as the component being
broken rather than as the host refusing it.

So those four are checked before anything a config says. A carve-out rather than
an ordering constraint on the pass, so the property holds wherever the pass runs.

### Where it runs — and why not over the expansion

`Policy::check_view` runs over the **shadow parse** (`dyncomp/host/bundle.mbt`,
`screen_view`): a throwaway tree in a throwaway `ParseContext`, before anything
is registered. That timing is right and the sanitizer should keep it. But it
means the tree is *unexpanded*: `MacroCall.node` is `None` until
`ParseContext::compile` runs, so a macro body is not in the tree yet.

The tempting fix — sanitize after `compile()` — is wrong twice. It registers the
components before deciding (the thing `screen_view` exists to avoid), and by
then a node no longer knows which *text* it came from, so a host macro's body
and a guest's slot content get judged under the same config even though they
came from different authors at different trust levels.

The right shape is to sanitize **each source text where it is registered**, under
the config for whoever wrote it:

- a guest view: at `screen_view`, unexpanded, under the guest's config;
- a macro's raw view: once, when the macro is registered, under its author's
  config.

Then expansion composes two already-checked trees and needs no third pass.

### The walk, and the one `for_each_child` gets wrong

`ANode::for_each_child` (`anode/anode.mbt`) has two blind spots, and
`has_raw_html` inherits both:

- `MacroCall(d) => if d.node is Some(node)` — nothing before expansion;
- `MacroData.slots` is not visited **at all**. Those are the caller's own
  subtrees, keyed by slot name (`ParseContext::new_macro_node`).

The second was reachable: `<x:card><div @dangerouslysetinnerhtml=".payload"></div></x:card>`
passed `check_view` with no refusal. (It only *renders* if the host registered a
macro named `card` whose body places the slot, so it was contingent, not
unconditional — see `dyncomp/SECURITY.md` §3. `sanitize_test.mbt` pins both the
old predicate's answer and the new walk's.)

The sanitizer has its own walk rather than a fix to `for_each_child`, because
`set_data_attr` and `collect_registered` share that function and adding `slots`
would make them stamp and index the same subtree twice once expansion has run.
The sanitizer walk visits `Dom.childs`, each wrapper's `.node`, `Slot.node`, and
`MacroCall.slots` — and *not* `MacroCall.node`, since by the rule above the
macro's body was checked at its own registration.

`Policy::check_view` now runs the sanitizer instead of `has_raw_html`; the
predicate stays in `anode` for other callers, still with its blind spot.

### It reports; it does not strip

The spec sanitizes by removal. This pass does not:

- for a guest bundle, removal is worse than refusal — the component silently
  renders wrong, and its author gets nothing to read. `dyncomp` already made
  this call for capabilities ("a capability that is present but lies is worse
  than one that is absent"), and it is the same argument;
- the tree is shared and mutable (`slots` aliases the expansion), so a stripping
  pass has an aliasing problem that a reporting pass does not have.

```moonbit
pub(all) enum Violation {
  Element(tag~ : String, at~ : String)
  ElementUnwrapped(tag~ : String, at~ : String)
  Attribute(tag~ : String, name~ : String, at~ : String)
  Comment(at~ : String)
  RawMarkup(tag~ : String, at~ : String)
}

pub fn Sanitizer::check(self : Sanitizer, tree : @anode.ANode) -> Array[Violation]
```

`at~` is a locator (`div>ul>li`) so a guest author can find it. `Violation` is
structured rather than a string because the wording belongs to the caller:
`policy` turns one into a `Refusal`, `lint` would turn the same one into an
advisory line.

### What the tree cannot express

Attributes in anode have no namespace — `AttrItem::Plain(name~ : String, …)` —
while the spec keys every attribute by (name, namespace), defaulting to null.
The practical casualty is `xlink:href` on an SVG child, which reaches the DOM as
a plain lowercased name and is a live URL sink. The static pass can only treat it
as the literal name `xlink:href`; the value side is Pass 2's problem anyway, so
this is a documentation gap rather than a hole — but it is why the port cannot
claim to be the spec's model exactly.

Two more names the allowlist has to own, because vdom applies them off the
ordinary attribute path:

- `is` — read at `to_dom.mbt` before `create_element` and passed at construction,
  because a later `set_attribute` does not upgrade a customized built-in. By the
  time any render-side check could see the element, it has been upgraded.
- `value` / `checked` — applied last, deliberately, but through the same
  `set_prop`, so nothing special is needed beyond knowing they are not missing.

## Pass 2 — a filter between render and diff

**Implemented** as `vdom/filter`: the `VdomFilter` trait, `UrlFilter`, and the
`App::set_filter` seam.

What Pass 1 cannot decide is exactly what the Sanitizer API declines to decide:
attribute values, and the payload of a raw-markup directive. Both are concrete
by the time a `Vdom` tree exists and before anything touches the DOM, and that
gap is a real seam in the code — `app/loop.mbt`, `App::render_now`:

```moonbit
match @render.render_root(root_val, stack, ctx) {
  Some(vdom) => {
    let prev = self.prev
    self.prev = Some(@vdom.render(vdom, self.root_node, self.opts, prev?))
  }
  None => ()
}
```

`render_root` finishes evaluating anode; `@vdom.render` diffs and morphs. A
filter goes between them:

```moonbit
pub(open) trait VdomFilter {
  fn filter_tree(Self, @vdom.Vdom) -> Unit
}
```

`App` holds a `mut filter : &VdomFilter?`, installed with `App::set_filter`.
**Absent is the trusted case and costs nothing** — not a branch per attribute, an
`if` per render.

It returns `Unit` and mutates, which is load-bearing rather than a style
preference: morph short-circuits a subtree by physical identity, and the render
cache hands back the same `Vdom` object when a site's inputs have not changed,
so a filter that rebuilt nodes would quietly turn every render into a full diff.
`VElem.attrs` is a mutable `Map`, so dropping an attribute costs no allocation
and no identity.

Installing is not retroactive — a value already in the DOM stays until something
re-renders over it — for the same reason a policy applies at load: retracting
what is already on the page is dropping it, not filtering it. There is a test
for that.

This is better than putting the rule inside `vdom` for four reasons:

- **It has the config.** A filter is constructed by whoever knows the trust tier,
  so raw markup stops being a separate later phase (see below) and the rule stops
  having to be a universal invariant to be reachable at all.
- **It is per-subtree, not per-app.** Every element a view compiles carries
  `data-cid` (`View::compile` → `set_data_attr`), and the render meta comment
  `§Comp§` carries `nid`/`cid`/`vid` (`render/cache.mbt`). Descending, a `data-cid`
  switches the config in force for that subtree. So a guest's components get
  sanitized and the host's own tree beside them does not, in one walk.
- **It sees what `set_prop` cannot.** `is` is read off the vnode before
  `create_element` (`to_dom.mbt`) because a later `set_attribute` will not upgrade
  a customized built-in; a filter over the tree can remove it, a filter inside
  `set_prop` never sees it.
- **It is where the feedback is.** A filter in warn mode names the view (`data-vid`)
  and what it dropped — the diagnostic Pass 1 cannot produce, because the value
  did not exist yet.

The chokepoint argument for `set_prop` — that a hand-built vnode walks around
anything higher up — does not survive contact with the threat model. The attacker
here is a bundle, and a bundle does not choose the render path; the host does.

### The rule

For attribute names in the URL set — `href`, `src`, `srcset`, `action`,
`formaction`, `ping`, `poster`, `data`, `background`, `xlink:href` — normalize
and reject a dangerous scheme:

1. strip leading and embedded ASCII whitespace and C0 controls (`java\tscript:`
   is the classic), lowercase;
2. take the prefix up to the first `:`, if that `:` precedes any `/`, `?` or `#`;
3. deny `javascript` and `vbscript` outright; deny `data` on the navigational
   names (`href`, `action`, `formaction`, `ping`, `xlink:href`) and allow it on
   the media ones, since `<img src="data:image/png;base64,…">` is ordinary and
   `<a href="data:text/html,…">` is a same-origin document;
4. no scheme at all is a relative URL and always fine.

A denied value **drops the attribute, not the element**: the link stops being a
link and everything else about it survives. It is also recorded — `UrlFilter`
keeps a bounded log a host drains with `take_reports()`, because by the time this
runs there is no author to report to. The value may have come from application
state rather than from anyone's template, so "why did my link vanish" needs an
answer that a parse-time diagnostic cannot give.

Two details the tests pin, both of which a simpler implementation gets wrong:

- **Normalization comes before comparison.** Tab, newline and carriage return are
  stripped from *anywhere* in a URL before a browser reads the scheme, so
  `java&#9;script:` is `javascript:` and a comparison that skips this step is a
  comparison against the wrong string. Leading C0 characters and spaces are
  trimmed, and a `:` only introduces a scheme when it precedes any `/`, `?` or
  `#` — otherwise `/a/b:c` would read as scheme `/a/b`.
- **`srcset` and `ping` are lists.** One is comma-separated candidates with
  descriptors, the other whitespace-separated URLs. Checking the whole string
  would let `"a.png 1x, javascript:… 2x"` through.

### Raw markup comes back here, not later

**Implemented** as `vdom/filter/markup` — its own package, because it drags an
HTML parser and the config model behind it and a host that only wants the URL
rule should not pay for either.

`@dangerouslysetinnerhtml` is unknowable at registration. The filter is where it
stops being unknowable: `eval_attrs` has already turned it into `Html(string)`
(`render/render.mbt`), `anode` already exposes a real fragment parser
(`parse_fragment`, over `moonbit-community/html/src`), and the filter is holding
the config. That the filter HOLDS a config is the whole reason this is the same
mechanism as the URL rule rather than a third one — it could not have been, if
the value rule had ended up a config-less invariant buried in `set_prop`.

**But do not re-serialize.** The obvious port of `setHTML()` is parse → prune →
serialize → `set_inner_html`, and an earlier draft of this document said exactly
that. It is wrong, and wrong in the way that has bitten every sanitizer which
shipped it: the browser then parses the string a *second* time, and any
disagreement between the two parsers is a mutation-XSS vector. Markup that looks
inert to `moonbit-community/html` can come back to life in Blink's.

So the filter builds **vdom nodes**. The payload is parsed once, sanitized as a
tree, and the result replaces the element's children — `set_inner_html` is never
called, because the attribute `set_prop` looks for is gone by then. There is no
second parse to disagree with. This is also what the platform actually does:
`Sanitizer` operates on nodes, and `setHTML` parses once.

Three consequences worth stating:

- With the filter installed, `@dangerouslysetinnerhtml` sets CHILDREN rather than
  `innerHTML`. Declared children are replaced, which is what `set_inner_html`
  did, so nothing silently changes there — but the result now diffs like ordinary
  children instead of being re-parsed on every render.
- The built subtree is checked **by the builder**, attribute values included. No
  filter runs after the one that created those nodes, so it is checked there or
  nowhere. That is why `attr_value_allowed` is public.
- Without the filter installed, the directive behaves exactly as it always has.
  Installing it is what makes the construct safe rather than merely dangerous.

### Doing the work once

Neither of these is implemented — the filter today is a full walk over the
finished tree, which is correct and is the thing to measure against.

**The static pass can hand the filter a skip set.** Pass 1 already visits every
attribute of every node and already distinguishes `Const` from a `Val`
expression. A view whose URL-set attributes are all constant, and which has no
`RawHtml`, has *nothing* left for the filter to decide — Pass 1 settled it. That
is a per-view bit computed once at registration, and the filter skips those
subtrees by `data-vid`. The views that need runtime work are the minority, which
is the whole argument for having a static pass at all.

**The filter should run at cache-miss, not over the finished tree.** The render
cache (`render/cache.mbt`) stores the rendered `Vdom` of a render site and hands
it back when the instance, site and binds are unchanged — `@vdom`'s morph then
short-circuits it by physical identity. A filter applied to the finished tree
re-walks those reused subtrees on every render for no result, and worse, a
sanitized subtree that gets cached and re-filtered pays twice forever. Filtering
where a site is *built* means each subtree is sanitized once per actual rebuild,
and a cached subtree is already clean by construction.

That argues for the filter being reachable from `render` rather than applied
after it, even though the seam it conceptually occupies is the one in
`App::render_now`. Cheapest honest version: `RenderCtx` carries the
`&VdomFilter?`, the cache-miss path applies it, and `App` owns installing it.
Worth measuring before committing — `benchmarks/OPTIMIZATIONS.md` #8 is the
precedent for a cache whose bookkeeping cost more than it saved.

### What the trusted case gives up

A null filter means a host app's own views get no URL check, and their dynamic
values come from application state that routinely includes user-supplied data.
That is a real loss versus a universal invariant, and it is **still open**: the
seam ships with `None` as the default, so today an app opts in with
`App::set_filter(Some(@filter.UrlFilter::new()))`.

The answer, when someone takes it, is to make the default *installed* rather than
absent — opt-out for an app, mandatory for a guest, zero configuration for
either. That is a behaviour change for every existing tutuca app, which is why it
is a separate decision from building the seam.

Unrelated to the filter, and belonging with Pass 1: `set_prop` routes by
`node.has_property(name)`, and `onclick` *is* a property, so an `:onclick="…"`
attribute takes the property path where a string assignment does nothing — and
would take the attribute path, which compiles a handler, if `try_set_prop_ffi`
ever returned false. That the attack fails today is an accident of routing, not a
defense. Pass 1 removing the name is the fix; a test that pins the behaviour
belongs with it either way.

## Order of work

1. ~~`anode/sanitize`: types, `validate()`, the baseline, the walk, `check()`.~~
   **Done** — 16 tests, covering the spec's validity table, the baseline holding
   against a permissive config, the reserved-data-attribute carve-out, and the
   macro-slot case that the old predicate missed.
2. ~~`Policy::check_view` runs the sanitizer instead of `has_raw_html`.~~
   **Done** — the refusal message gained the element and a locator.
3. ~~The `&VdomFilter` seam with a null default, and the URL rule as the first
   filter.~~ **Done** — `vdom/filter` (10 tests over the scheme table) plus
   `App::set_filter` and 3 end-to-end tests through the real render loop.
4. ~~The dyncomp host installs one, so a loaded bundle gets Pass 2 and not only
   Pass 1.~~ **Done** — `set_app` (`dyncomp/host/wasm/glue.mbt`) calls
   `set_filter` beside the policy and the GC sweep, and `take_filter_reports()`
   drains the log. That one line lives in the wasm glue, which `moon test` never
   runs; it is verified by inspection like the rest of the `tcomp` bridge.
5. ~~Raw markup re-admitted through the same filter.~~ **Done** —
   `vdom/filter/markup`, 9 tests. Available to any host that installs it; the
   case it helps most is a plain tutuca app rendering
   `@dangerouslysetinnerhtml` over data it did not write.

What is left, in rough order of who it helps:

- **Install the filter by default for a plain app** — the one that helps every
  tutuca app rather than only a dyncomp host, and a behaviour change for every
  existing one, which is why it is its own decision.
- **Let a `Policy` carry a `SanitizerConfig`**, so a dyncomp host could allow a
  guest raw markup. Deliberately NOT done as part of step 5: `Policy::check_view`
  has no way to know whether the markup filter is installed, so a policy that
  said `raw_markup: true` next to an app mounted without the filter would send
  the payload straight to `set_inner_html` unchecked. Guests are still refused
  the construct outright, and loosening that should be one explicit decision
  rather than a side effect of the capability existing. `dyncomp` therefore
  installs the URL filter only — the markup filter would never fire there today,
  and would cost a walk per render for nothing.
- **The skip set and cache-miss placement**, measured rather than assumed.
- **A guest-level end-to-end test.** `app/filter_test.mbt` proves the filter sees
  what the render loop builds, and a guest's subtree is part of that same tree by
  construction — so this would add little, and the scaffolding is a whole
  `DynManifest`. Worth it only if the composition ever stops being obvious.
- **The spec's default allow-list is not transcribed** (see above). Until it is,
  `default()` is the baseline and a host supplies its own allow-list.
- **`set_prop` routes `onclick` by `has_property`**, so the attack fails today by
  accident of routing rather than by defense. Step 1 removes the name at
  registration, which is the actual fix, but a test pinning the vdom behaviour is
  still owed.
