# Sanitizing an anode view

The design, and what became of it. It exists because `tgc/host` compiles view
text it did not write into the host's own page, and because
`tgc/SECURITY.md` §7 promises a port of the [WHATWG Sanitizer
API](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#sanitizer)
without saying what "port" means for a tree that is half description and half
expression. This says it. It lives in `anode/sanitize` and `vdom/filter`, and
each section marks the parts that are argued for rather than built.

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
baseline is script-bearing elements (HTML `embed`, `frame`, `iframe`, `object`,
`script`, and SVG `script` and `use`) and event-handler attributes; its own default
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

**Implemented.** A leaf package over `anode`. `tgc/policy` imports it for the
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

### The baseline comes from the spec, never from a summary

The spec's baseline lists **`script` twice** — once in HTML's namespace and once
in SVG's. Element identity here is namespace-qualified (`ElementName::key`
prefixes `svg:`), so `html("script")` never matched the `<script>` inside an
`<svg>`, and

```html
<div><svg><script>alert(1)</script></svg></div>
```

passed `Sanitizer::check` with **no violation at all** — through `check_view`,
into a registered guest component, and onto the host's page. An SVG `<script>`
inserted through the DOM executes.

`unsafe_elements` is held against `spec_baseline_removes` by a test, and
that array is generated from the spec's own baseline file rather than typed. The
test asserts *containment*, not equality, because tutuca also refuses `base` —
a `<base href>` retargets every relative URL on the host's page, which is worth
refusing outright even though the spec leaves it to the config layer. The
difference is asserted explicitly so that a regeneration which silently absorbed
it would fail.

The general rule, which is now in `AGENTS.md`: never hand-transcribe an
allow-list, and never take one from MDN or a blog post. Both directions of error
are bad, and only one of them is visible.

### Safety comes from the entry point, not the config

`Sanitizer` applies the unsafe baseline — the unsafe elements, and every
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

The **baseline** (`removeUnsafe()`) is the unsafe elements and the event
handlers. The **default configuration** is a large allow-list of elements with
per-element attributes, which *additionally* drops comments and `data-*`.
MDN is explicit that the second is not the first: "calling `removeUnsafe()`, or
passing a custom sanitizer to the safe sanitization method, only removes the
XSS-unsafe items. It does not remove the additional items, comments, and `data-*`
attributes."

`SanitizerConfig::default()` here is the empty config, so the sanitizer is the
baseline alone.

**The spec's default allow-list is now transcribed**, as
`SanitizerConfig::spec_default()` — but it is offered, not imposed, and it is
NOT what `default()` returns. The reason is not caution: the spec's default
configuration allows **no interactive or media element at all**. No `button`, no
`input`, no `img`, no `form`, no `select`, no `label`. That is right for what it
is for — pasting document content into a page — and wrong for a tutuca view,
which describes an interactive component. Adopting it as the default would
refuse essentially every real guest, starting with any that has a button. A host
whose guests really are document content (a comment renderer, a CMS body) hands
it to `Policy::with_sanitizer` and gets the platform's own answer.

It is **generated**, by `scripts/fetch-sanitizer-defaults.mjs`, from the
machine-readable `builtins/` in the spec repo at a pinned commit — which is what
the spec's own prose is generated from, so it cannot disagree with the text the
way a hand transcription can. That mattered immediately; see below.

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

`Policy::check_view` runs over the **shadow parse** (`tgc/host/bundle.mbt`,
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
unconditional — see `tgc/SECURITY.md` §7. `sanitize_test.mbt` pins both the
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
  renders wrong, and its author gets nothing to read. `tgc`'s policy
  already made this call — a bundle that needs what a host withholds is
  refused whole rather than loaded drawing half of itself — and it is the same
  argument;
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
`App::set_sanitizer` / `App::add_filter` seam.

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
  fn take_reports(Self) -> Array[Dropped] = _   // defaults to none
}
```

`App` holds a `mut filter : &VdomFilter` — never absent — built from the
sanitizer it also holds. **The chain is installed by default and there is no
opt-out**; see "What a host may change, and what it may only narrow".

`take_reports` is on the trait rather than on each filter because the filter
that drops something is now usually one the host never constructed. Draining it
had to work without the concrete type, or the default would be a silent
dropper.

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

### Markdown comes back the same way, and needs no permission

**Implemented** as `vdom/filter/markdown`: the `@setinnermd` directive,
`MdFilter`, and the vendored parser in `markdown/`.

`@dangerouslysetinnerhtml` is the construct a host has to think about. The
construct people actually *want* most of the time is narrower: render some
markdown that the app did not write — a comment body, a CMS field, an LLM
response. Before this, that meant shipping a JS markdown library and handing its
output to the dangerous directive, which is the worst available shape: a second
parser, outside the sanitizer, feeding a string to `innerHTML`.

`@setinnermd` takes the markdown SOURCE. It reaches the DOM through
`Block`/`Inline` → `@vdom.h`, and **every element it emits goes through
`element_verdict` and every attribute value through `attr_value_allowed`**,
routed through one `emit` helper so no arm of the walk can forget. There is no
HTML string anywhere in the path.

That is why the directive's name carries no warning and why **Pass 1 never
refuses it**. `raw_markup` is a permission because a raw-HTML payload arrives as
markup the config gets no say over — refusing the construct is the only lever
there is. Markdown has no such route, so there is nothing to permit; a host that
wants less says which elements it will have, the same way it does for every
other node in the tree. `filter_for` therefore installs `MdFilter`
unconditionally and reads no field for it.

Three things this cost that were not obvious:

- **Markdown filtering lives in `vdom/filter/markdown`.** The chain is
  `[MarkupFilter?] → MdFilter → Baseline`, and `markup` cannot express that —
  the dependency runs `markdown` → `markup` and a cycle is not available. A
  host wanting the raw-markup rule and nothing else builds the pair itself:
  `@filter.Chain::new([@markup.MarkupFilter::new(sanitizer~), @filter.Baseline::new()])`.
- **`set_prop` fails closed on `setInnerMd`** (`vdom/to_dom.mbt`). Reaching it
  means no filter consumed the attribute, and the element is CLEARED. Rendering
  the markdown as text would be wrong output; passing it to `set_inner_html`
  would turn the one directive whose name promises safety into the most
  dangerous in the framework. `render_wbtest.mbt` pins both halves — nothing
  without a filter, real nodes with one.
- **`App::new` installs it**, so `@setinnermd` works with no configuration. The
  price is that every app links the ~4.7k-line parser, since the call is
  unconditional and nothing about it is dead.
  There is no way to trade it away: the seam takes a policy, and the parser is
  behind a rule the policy does not reach.

### HTML and SVG come back the same way, and need no permission either

**Implemented** as `vdom/filter/markup/safe.mbt`: the `@setinnerhtml` and
`@setinnersvg` directives and the `SafeMarkupFilter` that consumes them, over
the same `html_nodes` builder `@dangerouslysetinnerhtml` uses and a new
`svg_nodes` beside it.

The argument that made these two obvious is one this document had already
written down without noticing. `@setinnermd` routes `HtmlBlock` and
`HtmlInline` straight through `html_nodes`, `MdFilter` is installed by
`App::new`, and neither reads a permission. So **"an arbitrary runtime string
becomes sanitized HTML nodes, unpermissioned" is what a default app has always
done** — an author who wanted it just had to wrap the payload in a markdown
document to reach it. Naming it directly adds no capability; it removes a
detour.

What makes the safe name honest is not the filter, which a host could fail to
install. It is that `set_prop` **fails closed** on both names, the way it
already did on `setInnerMd`: no filter, empty element. That is the difference
from `@dangerouslysetinnerhtml`, whose fallback is `set_inner_html`, and it is
why `raw_markup` is a permission and these two are not. There is no unchecked
path to permit, so Pass 1 waves them through and the filter reads no field.

Three things worth stating:

- **The SVG one is not the HTML one restricted to `<svg>` payloads.** It parses
  in SVG context (`@anode.parse_fragment_svg`, which wraps in `<svg>` and hands
  back the wrapper's children), so a bare `<circle/>` works and the payload
  cannot leave the namespace it was promised. The one way back to HTML is
  `<foreignObject>` — and that route is the *parser's* doing, which is what
  makes it safe: the contents are labelled HTML, so `html("script")` on the
  baseline covers them without anything here special-casing it.
- **They narrow CSS, and nothing else does.** The narrowing is an overlay beside
  the baseline — not a config, because `remove_elements` cannot coexist with an
  `elements` allow-list under the spec's validity relation, so a merged config
  would raise for exactly the hosts that configured most carefully.

  There is a CSS parser now — `anode/sanitize/css`, and `docs/css-validator.md`
  — so the overlay is
  `Sanitizer::with_css(@safecss.CssPolicy::payload())`: the `style`
  ATTRIBUTE is parsed and re-emitted rather than dropped, and the `<style>`
  ELEMENT stays refused, because a stylesheet is selectors and at-rules as well
  and only the declaration half is built. `without_css()` remains, as
  `with_css(CssPolicy::deny())`.
- **`@setinnermd` narrows the same way, and it took a value rule to let it.**
  Doing it at the filter would take GFM column alignment with it —
  `style="text-align:left"`, written by `build.mbt` itself — which is a rendering
  bug, not a tightening. The split is who authored the value, a question a NAME
  rule cannot ask.

  A value rule does not need to ask it: `text-align:left` is admitted at the
  smallest level there is and a payload's `background:url(…)` is admitted at
  none, so the answer is the same for both authors. `filter_for` narrows once, on
  the way in, and `Build` carries one sanitizer again.

Two things that fell out of writing them, neither of which is about the new
directives:

- **SMIL was a hole in the baseline.** `<animate>`, `<animateMotion>`,
  `<animateTransform>` and `<set>` assign the attribute named by
  `attributeName` in the browser, *after* `check` has read the tree and after
  the render-time filter has read the built nodes — so the `href` anything
  checked is not the `href` that navigates. `tgc/policy` already refused all
  four for an untrusted guest; the baseline did not, and a plain app has no
  Pass 1 at all. They are in `unsafe_elements` now.
- **Namespaced attributes had a spelling nothing else knew.** The parser
  implements WHATWG 13.2.6.4 faithfully and hands back `xlink href`,
  space-separated, where the source said `xlink:href`. `@filter.url_attrs` knows
  the colon form, because that is the only spelling a *view* can write — so
  `<a xlink:href="javascript:…">` inside any payload walked past the URL rule.
  It would also have reached `set_attribute("xlink href", …)`, which throws.
  `foreign_attr_name` in `nodes.mbt` folds it back before any rule reads it.

#### Two findings from the parser that the design rests on

Both are pinned by `markdown/parse_test.mbt`, and a re-sync that moves either
one needs the builder revisited before it lands.

**Inline raw HTML is only ever an HTML comment.** `Inline::HtmlInline` is
produced from exactly one place upstream — `try_parse_html_comment` — so it is
always a complete `<!-- … -->`. Together with `Block::HtmlBlock` being a whole
run of lines, that means every raw-HTML carrier in the AST is self-contained and
can go to `@anode.parse_fragment` on its own, through the same `html_nodes`
builder `@dangerouslysetinnerhtml` uses. There is no half-open tag to reassemble
across siblings — which is the thing that would otherwise have forced an
AST→HTML-string step, and with it the second parse.

It is also why upstream's HTML renderer is not vendored. The plan for this work
said "AST → HTML string → parse → sanitize"; the finding is what removed the
middle two steps.

**A bare inline tag becomes a bogus autolink, not text.**
`try_parse_autolink` accepts *any* `<…>` with no whitespace in it, so `<span>`
arrives as `Autolink(url="span")` and `</span>` as `Autolink(url="/span")`.
Neither is a link. The builder therefore renders an `Autolink` as an `<a>` only
when the URL carries a real scheme (`@filter.scheme_of`), and as the literal
text `<url>` otherwise. Without that rule a comment body containing ordinary
HTML would fill up with stray links to relative paths — not a security hole,
since a relative URL is allowed, but visibly wrong.

The consequence for a reader: inline HTML tags render as the characters the
author typed. That is a divergence from CommonMark, inherited from the parser
rather than chosen, and it is the safe direction to diverge in.

#### The concrete reason not to serialize

The "do not re-serialize" argument above is general. Rendering the landing-site
example in a real browser and reading the DOM back produced a specific instance
of it, and it is worth stating because it is the kind of thing that reads as a
bug until you follow it through.

`java&#9;script:` reaches the sanitizer by two routes, and they are safe for
**different** reasons:

- **As raw HTML** (`<div><a href="java&#9;script:…">`), `@anode.parse_fragment`
  is a real HTML parser, so it decodes the entity to a tab before anything looks
  at the value. `attr_value_allowed` strips the tab, reads the scheme as
  `javascript`, and denies it. The normalization does exactly the work it exists
  for.
- **As a markdown link destination** (`[x](java&#9;script:…)`), nothing decodes
  it — markdown has no entity rule there — so the value stays literal. The
  scheme is `java&#9;script`, which no browser registers, and the attribute
  reaches the DOM through `setAttribute`, where entities are not a thing. It is
  never `javascript:` at any point, and the link navigates nowhere.

**The second is what a serializing design gets wrong.** Write the sanitized tree
back out as HTML text and hand it to `innerHTML`, and the browser's parser
decodes `&#9;` on the way back in: the value this code correctly allowed as an
unknown scheme becomes `java\tscript:`, which Blink normalizes to `javascript:`
and fires. Same input, same sanitizer, opposite outcome, and the only difference
is the second parse.

That is mutation-XSS in one line, on a value neither parser handled wrongly.
`markdown_test.mbt` pins both routes.

#### Two divergences that are ours, not the parser's

- An unbalanced `HtmlBlock` (a lone `<div>` line) auto-closes inside its own
  fragment, so markdown that followed it becomes a **sibling** rather than a
  child. There is no partial element to leave open across a boundary when what
  you are producing is a tree.
- `style` on a table cell is the only attribute this package synthesizes, so a
  config with a global `remove_attributes` naming `style` drops the alignment.
  That is the config doing its job.

#### Two failure modes, and the split is not the obvious one

An attack in a markdown document fails in one of two ways, both safe, and which
one it gets is decided by mizchi's block parser rather than by anything here:

- an opener it **recognises** as an HTML block goes through
  `@markup.html_nodes`, becomes an element, gets a verdict, and is dropped with
  a `Dropped` report — `<svg><script>`, `<iframe>`, `<base>`, `<div onclick>`;
- an opener it **does not** falls through to the inline parser and lands as a
  TEXT node. `createTextNode` output can never be parsed as markup, so it is
  inert, and nothing is reported because nothing was dropped — it was never
  markup to begin with.

**A bare `<script>` is in the second group**, as are `<object>` and inline
`<span>`. That reads alarming in any output that prints text unescaped, and it
is why the verification for this feature asked the DOM for a `script` element
COUNT rather than grepping a serialized string.

`markdown_test.mbt` pins the split, because a parser bump is exactly what would
move a case across it: an upstream that adds `script` to its HTML-block list
flips that one from "text, no report" to "dropped, one report". Still safe,
but a visible change to what the landing-site example demonstrates.

#### One thing to be careful reading in the tests

memdom's `to_html()` does no entity escaping — it says so at the top of
`vdom/memdom/serialize.mbt`, being a test aid rather than a sanitizer. So the
characters `<script>` DO appear in its output for a document containing an
inline `<script>` tag, as a TEXT node that reaches the browser through
`createTextNode` and is inert. Assert on what elements the tree contains, not on
the serialized string: one way round you read an inert text node as a hole, the
other way you pass only because of how a debug helper prints.
`app/filter_test.mbt` carries this warning beside the test that needed it.

### Doing the work once

**The filter runs where an element is CONSTRUCTED.** `render` builds an element
in exactly one place (`render/render.mbt`, the `Dom(d)` arm), and `RenderCtx`
carries the filter so it can be applied there. That is exactly-once by
construction, costs no traversal at all, and means a subtree the render cache
hands back was never rebuilt and so is never re-filtered.

Two attempts preceded it, and the first was what shipped:

- **Over the finished tree**, in `App::render_now`. Correct, and the wrong
  complexity: the render cache returns the same `Vdom` object for an unchanged
  site and morph then short-circuits it by physical identity, so the filter did
  O(whole tree) work beside a pipeline that is otherwise O(changed). On a
  1000-row list, morph touches one row and the filter touched all thousand.
- **A walk that stops at nested `§Comp§` boundaries**, applied to each body at
  the cache miss. This does not work, and the reason is worth writing down:
  `@vdom.fragment` FLATTENS nested fragments (`normalize_childs` in `vdom/h.mbt`),
  so a nested component's `[§Comp§ meta, body]` is spliced inline into its
  parent's child list. There is no nested fragment left to stop at, and no
  marker for where the child's content ends. A test that counted filtered
  elements caught this immediately — 9 where 6 was expected, the child's three
  counted twice.

`app/filter_test.mbt` pins the result: six elements across a parent and a nested
child are filtered six times on the first render, and a change to the parent
alone re-filters three.

Two consequences of hooking construction rather than a walk:

- **Installing anything clears the render cache.** A cached subtree carries the verdict
  of whichever filter was installed when it was built, so keeping them would
  mean a newly installed filter never saw most of the tree. One full rebuild, on
  a call a host makes about once.
- **A filter that replaces children owns what it builds.** Children are already
  built when `filter_elem` is called, and nothing runs after it on nodes it
  created — so `MarkupFilter` sanitizes its own output, attribute values
  included. That was already true by design; it is now load-bearing rather than
  belt-and-braces.

### The tree says which rules could apply, and mostly says none

**Every attribute NAME in a view is a literal.** That is the same fact
`Policy::check_view` rests on, and it means the first half of every rule here —
does this name concern me — is decidable off the tree, once, with the same
answer on every render. Only the second half, the value, needs the filter.

`@sinks.SinkHints` carries the first half: four bits (`url`, `handler`, `css`,
`markup`), computed by `render` from anode's attributes using `vdom/filter`'s
own predicates, memoized on `DomData`, and passed to `filter_elem_hinted`. A
rule whose bit is clear returns without reading the attribute map at all, which
for most elements removes nearly all of what the filter would otherwise do. The
filter's remaining cost sits inside the measurement noise —
`benchmarks/OPTIMIZATIONS.md` §13 has the numbers and the package-boundary
reasons the type lives in a directory of its own.

It is safe by construction rather than by argument: the trait method **defaults
to ignoring its hints**, so a filter this repo does not own sees every element
as before; a missing hint means `SinkHints::all()`; and the fold only ever sets
bits. Only a hint that is too NARROW could cost anything, and the one way that
could happen — `Attrs` being mutable after the walk — is `set_data_attr`, whose
callers write `data-*` names that no rule looks at. There is a test for exactly
that.

The remaining idea from this section is not implemented, and it is the VALUE
half of the same thought:

**The static pass can hand the filter a skip set.** Pass 1 distinguishes `Const`
from a `Val` expression, so a view whose sink-set attributes are all constant,
and which has no `RawHtml`, has *nothing* left for the filter to decide — Pass 1
settled it.

What the name half above did not need, and this does: **something has to have
checked those constants.** `Policy::check_view` has one call site
(`tgc/host/bundle.mbt`), so Pass 1 runs for a guest module and nobody else.
For a plain app "constant" means "nothing ever looked at it", and skipping a
constant would hand back the literal `javascript:` URL and the literal `onclick`
that installing the filter by default removed. So this one is not free the way
the name half was. It needs one of:

- **a compile-time check of constants for a plain app too** — which is where the
  diagnostic belongs anyway, since a constant `javascript:` href is an author
  error and Pass 2 has no author to report it to; or
- **a host that can promise the policy which checked a constant is no stricter
  than the one filtering now** — which is a property of the app's API, not of
  the tree. See "What a host may change, and what it may only narrow".

### Why the sanitizer is always on, and why hosts may only narrow it

`App::new` installs the built-in chain for every app: the trusted case would
otherwise pay nothing and get nothing, while every app that has never heard of
the seam carries the risk. A default that is safe and a narrowing API that is
one call is the right way round; the reverse asks every author to know about a
document they have not read.

**A filter is opaque.** `&VdomFilter` is a trait object, so "is the one you are
installing at least as strict as the one it replaces" is not a question any code
here can ask — there is no order on trait objects to ask it in. An API that
takes one can only offer REPLACEMENT, and replacement includes removal. The
three documented reasons to reach for `None` were a deliberate `javascript:`
URL, an all-developer-authored tree, and a hot render loop; the first is one
link, and it turned off the `on*` rule and the markup sanitizer to get it.

**Order between filters is load-bearing**, which a host cannot be asked to keep.
A filter that REPLACES a subtree must run before the ones that inspect
attributes, or the subtree it built is never inspected; `CssFilter` must run
before `Baseline`, because it rewrites values the URL rule reads. That is why
`@mdfilter.filter_for` exists — one function where the policy and the chain it
implies are named together — and a `set_filter` that let a host assemble its own
put that invariant back in the host's call sequence.

So the seam is a POLICY now:

```moonbit
app.set_sanitizer(sanitizer)   // what the built-in chain enforces
app.add_filter(my_rule)        // a rule of my own, BEHIND the built-in chain
```

- **`set_sanitizer`** changes what the chain enforces, never whether there is
  one. A `Sanitizer` is a value with structure — narrowing it is something a
  host can write down and `SanitizerConfig::validate` can check — and whatever
  it says, `filter_for` puts the same rules around it.
- **`add_filter`** is append-only and appends BEHIND. An addition sees a tree
  the built-in chain has already been over, so it can remove more and can never
  put back what was removed. There is no `remove_filter`, and no way to get in
  front. (The consequence to know: a rule added to watch for `javascript:` URLs
  will never see one — it is behind the defense, not beside it.)

**What this does NOT claim.** It is not "a policy may only get stricter": a
host installs `filter_for(policy.sanitizer)` for a policy that may
PERMIT raw markup, which is a widening, and refusing it would break the one
caller the seam was built for. The monotone property is narrower and is the one
that matters: *the built-in chain always runs, and anything a host adds can only
remove more.*

**What it costs.** A deliberate `javascript:` URL is not expressible —
accepted, and stated here rather than buried: it is rare, and the alternative
is an API where every app's defense can be removed by one call somebody writes
for one link. The other two reasons are answered rather than refused: an
all-developer-authored tree is hard to promise, and the hot render loop was
measured away (`@sinks.SinkHints`, `OPTIMIZATIONS.md` §13).

**What it means for tests**: the second layer — that a directive whose filter
never ran renders an empty element, and that `set_prop` refuses a structured
value on `href` — is not reachable through an `App`, so it is not an app-level
test. The properties stay pinned where they live, in
`render/render_wbtest.mbt` and `vdom/memdom/custom_element_test.mbt`.

Unrelated to the filter, and belonging with Pass 1: `set_prop` routes by
`node.has_property(name)`, and `onclick` *is* a property, so an `:onclick="…"`
attribute takes the property path where a string assignment does nothing — and
would take the attribute path, which compiles a handler, if `try_set_prop_ffi`
ever returned false. That the attack fails there is an accident of routing, not a
defense. Pass 1 removing the name is the fix.

`vdom/memdom/event_attr_test.mbt` pins this, and writing it turned up two things
the paragraph above had wrong:

- **On a namespaced element the attack does not fail at all.** `uses_prop` is
  `!namespaced && …` (`vdom/to_dom.mbt`), so an SVG or MathML element routes
  *every* attribute through `set_attribute` — `<svg onclick="…">` and
  `<circle onload="…">` are written as live content attributes, and SVG elements
  honour them. There is no accident of routing to rely on here, so this half is
  not "fails today by luck"; it is open until a name-dropping pass covers it.
- **memdom's `has_property` did not know about `on*`**, so it answered `false`
  and sent `onclick` down the `set_attribute` path — the opposite of a browser.
  Every test that might have asserted this attack fails would have asserted it
  against the wrong DOM. Fixed by `is_event_handler_prop` in
  `vdom/memdom/props.mbt`, using the same prefix predicate as
  `@sanitize.is_event_handler_attr`.

`never_assign` is *not* the fix, and there is a test saying so: adding `onclick`
to that set forces the attribute path on plain HTML elements too, which is
strictly worse. Its existing members are names whose attribute form is the
correct one, which an event handler's is not.

