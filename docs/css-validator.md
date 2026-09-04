# Validating a subset of CSS

`anode/sanitize/css` reads a declaration list, refuses everything it does not
understand, and **re-emits what is left canonically**. This is what
`tgc/SECURITY.md` §7 has been promising, and it is the answer to the one
question the WHATWG Sanitizer API declines to have an opinion about: attribute
VALUES. Its vocabulary is names, and `url(…)` and `position:fixed` both live in
a value.

This document says what the subsets are, what each covers and what each leaves
out, and the two findings that decided the design.

## Why a validator rather than a name rule

The alternative is to close CSS by refusing: drop the `style` attribute and the
`<style>` element outright, and refuse `fill`, `stroke`, `clip-path`, `mask`,
`filter`, `marker-*`, `cursor`, `list-style*` and `background-image` by name for
an untrusted guest, because CSS accepts `url(...)` in each of those SVG/HTML
presentation sinks.

A name rule cannot tell a constant `fill="#1da1f2"` from a dynamic
`fill="url(//evil.test/p)"`, so it refuses both. It also cannot tell who
authored the value: GFM column alignment is `style="text-align:left"`, written
by `vdom/filter/markdown/build.mbt` itself, so a filter that narrows CSS by name
either loses table alignment or needs a second sanitizer for the values it wrote.

Reading the value answers all of it, and `Build` carries one sanitizer.

## Two findings

### `mizchi/css/token` does not decode escapes, and no name check over its tokens is sound

`Tokenizer::consume_name` skips the backslash and copies the next raw character
— its own comment says "CSS hex escapes aren't decoded here". So

```css
background-image: \75 rl(https://evil.test/p)
```

tokenizes as `Ident("75") Whitespace Function("rl")`. Nothing in the token stream
says `url`, and every browser reads it as `url(`. `Token` carries no source span,
so the original spelling is not recoverable downstream: a validator built on
comparing function names against this tokenizer is bypassed by one backslash.

The answer is not a better comparison. It is `has_escape`: **refuse any input
containing a backslash, anywhere, checked on the raw string before tokenizing.**
A CSS escape spells a character you could have written directly, and nothing in
any level here needs one. The refusal closes the whole class rather than one
spelling of it.

(A scoped STYLESHEET could not do this — Tailwind emits `.bg-\[\#fff\]` and a
selector legitimately carries escapes. That is one reason the stylesheet half is
not built; see "What is left".)

Separately, `peek_char` returns U+0000 both for "the byte here is a NUL" and for
"there is no byte here", so an embedded NUL is end-of-input to everything inside
the tokenizer, where css-syntax-3 §3.3 says it is U+FFFD and the browser keeps
reading. `preprocess` does the §3.3 replacement first, so no NUL ever reaches it.

### Re-serializing CSS is safe, and this is the inverse of the HTML rule

`docs/sanitizer.md` argues at length never to re-serialize a sanitized HTML tree.
That argument does not carry over, and the reason is worth stating because the
mantra reads as if it did.

A sanitized HTML payload becomes **nodes**. The browser parses the source once,
and writing the tree back out as text adds a SECOND parse that can disagree with
the first — mutation XSS.

A CSS value is never nodes. It reaches the browser as a **string** the browser
parses, through `setAttribute("style", …)` or through a stylesheet, whatever this
code does. There is exactly one browser parse either way. Emitting our own
canonical string therefore does not add a parse; it removes the chance that ours
and theirs disagreed.

The consequence is the property everything else rests on: **a declaration list
that survives contains no byte the validator did not choose.** There is nothing
for an unparsed tail, a stray `}` or a cleverly-spelled function name to ride in
on, because nothing rides.

## The normalization phase

Before any rule reads anything:

1. **css-syntax-3 §3.3 preprocessing** — `\r\n`, lone `\r` and `\f` become `\n`;
   U+0000 and lone surrogates become U+FFFD.
2. **Refuse any `\`**, on the raw input.
3. **Refuse the whole list** on `BadString`, an unmatched paren, a brace, a
   bracket, `CDO`/`CDC`, or any at-keyword — the shapes where a recovery rule
   decides the meaning, which is where two parsers disagree.
4. **ASCII-lowercase** property, function, unit and keyword names; preserve case
   for custom property names, which are case-sensitive; refuse non-ASCII names.
5. **Caps** on declarations, tokens and nesting depth.

## The subsets

Two ordered **levels** and three **switches**, so a host can have layout without
ever having egress.

### `CssLevel::Deny`

No CSS. What `without_css` meant, kept as a level for a host that wants its
guests to style with its own classes and nothing else.

### `CssLevel::Constant` — paint and typography, no function anywhere

**Token vocabulary**: identifiers, hashes, numbers, percentages, dimensions,
commas, whitespace. No function token at all, no string.

**Covers**: `color`, `background-color`, `opacity`; the SVG paint properties
(`fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `stop-color`,
`flood-color`, …); type (`font-size`, `font-weight`, `line-height`,
`letter-spacing`, `text-align`, `text-decoration-*`, `white-space`, `hyphens`,
`writing-mode`, …); border and outline colour, style, width and radius;
`list-style-type`, `visibility`. Identifiers are checked against the **generated
per-property keyword table**, so `text-align: justify` is admitted and
`text-align: flex-start` is not.

**Leaves out**: every function, including `rgb()` and `calc()`; strings, so no
`font-family: "Helvetica"`; custom properties and `var()`; all layout and box
properties; gradients; transforms; positioning; `url()` unless the URL switch
allows a fragment.

**Why it is worth having on its own**: it is exactly the `text-align` a GFM table
writes, exactly `fill`/`stroke` on an icon, and essentially all of a comment
body's real styling. Nothing in it can compute, position, overlay or fetch.

### `CssLevel::Computed` — layout, and a closed set of functions

**Adds properties**: `display`, the sizing and box properties, `margin`,
`padding`, `overflow`, flex, grid, `gap`, alignment, `aspect-ratio`, the table
properties, `font-family`, `text-overflow`, the `background-*` painting
properties and the `background` shorthand, `border-image*`, `object-fit`,
`cursor`, `user-select`, and the SVG geometry properties.

**Adds functions**, each admitted by name with its arguments checked as ordinary
component values: the colour functions (`rgb`, `hsl`, `oklch`, `color-mix`, …);
the maths functions (`calc`, `min`, `max`, `clamp`, `round`, …); the gradients;
the easings; `fit-content`, `minmax`, `repeat`; the basic shapes; the filter
functions.

**`var()` and custom properties** are admitted, and this is the one decision
that needed its own test. A custom property's value is arbitrary tokens per the
spec, substituted without being re-checked, so `--x: url(evil)` followed by
`background-image: var(--x)` is the classic hole. It is closed at the
**definition site** — the only place a token can enter — by validating every
`--*` declaration under the same value grammar.

**Relaxes the keyword table.** An identifier is inert: it cannot fetch, execute
or move anything. The generated table unions grammars across every level of
every spec and still cannot know about the vendor keyword a real page uses, so
`Computed` admits any ASCII identifier and lets the browser reject
`display: nonsense` as invalid CSS. What holds the line here is the property
list, the function table and the URL rule, none of which an identifier reaches.

**Leaves out at both levels**: `attr()`, `expression()`, `image-set()`,
`image()`, `cross-fade()`, `element()`, `path()`, `counter()`; `content`;
`!important`; every at-rule; anything the normalization phase refused.

### Switch — `overlay : Bool`

Off by default. Gates `position`, `inset`/`top`/`right`/`bottom`/`left`,
`z-index`, the transforms, `pointer-events`, `mix-blend-mode`, `isolation`,
`box-shadow`, `text-shadow`, `filter`, `backdrop-filter`, `clip-path`, `mask*`,
`will-change`, `contain`, `content-visibility`, `view-transition-name`; and the
transform FUNCTIONS wherever they appear, so a property that happens to accept
one is not a way round the switch.

This is clickjacking, not script, and no scheme check sees it: a
`position:fixed; inset:0; opacity:0` element is an invisible sheet over the whole
page and every click on it belongs to whoever wrote the payload. It is separate
from the levels because a full-page guest wants layout and must still never get
egress.

`box-shadow` and `text-shadow` are in it because they paint outside the element's
own box. They cannot capture a click, so that is spoofing rather than
clickjacking — but a shadow the size of the viewport is a grey sheet over the
page, and the property costs nothing to gate.

### Switch — `url : UrlRule`

`NoUrl` | `FragmentOnly` | `Screened`.

- **`FragmentOnly`** admits `url(#name)` and nothing else. It fetches nothing —
  the target is an element already in the document — and it is the difference
  between an SVG subset worth having and one that is not, since `fill`,
  `marker-*`, `clip-path` and `mask` are how SVG points at a gradient or filter
  it defined itself.
- **`Screened`** hands each non-fragment target to a `screen` callback the caller
  supplies. The scheme rule is not reimplemented here — `@filter.url_value_allowed`
  already exists, and two URL rules that could disagree would be one too many.
  **`screen` defaults to refusing**, so asking for `Screened` and passing nothing
  behaves as `NoUrl` rather than as no check at all.

Only two spellings of `url()` are admitted: `url(#name)`, where the fragment is a
single `Hash` token, and `url("target")`, where it is a `String` token. The
**unquoted non-fragment form is refused**, and this is the one decision that
costs an author something. css-syntax-3 gives it its own token type
(`<url-token>`) with its own escaping and whitespace rules, which
`mizchi/css/token` does not implement — an unquoted `url(/a/b.png)` arrives as a
run of `Delim` and `Ident` tokens that would have to be reassembled by guessing
at rules the tokenizer did not apply. Reassembling a URL and hoping the browser
agrees is exactly the mistake this package exists not to make.

### Switch — `stylesheet : Bool`

Whether a `<style>` ELEMENT survives. A stylesheet is not a declaration list: it
is selectors and at-rules as well, and only the declaration half is built. True
for a page's own tree, false for everything else.

### The three named policies

| | level | overlay | url | `<style>` |
|---|---|---|---|---|
| `CssPolicy::deny()` | `Deny` | no | `NoUrl` | no |
| `CssPolicy::payload()` | `Computed` | no | `FragmentOnly` | no |
| `CssPolicy::app()` | `Computed` | yes | `Screened` | yes |

## Where the facts come from

`properties_gen.mbt` is generated by `scripts/fetch-css-properties.mjs` from
w3c/webref's `ed/css/*.json` at a pinned commit — the extracts the `@webref/css`
npm package ships — plus mdn/data for `<named-color>` and `<system-color>`, which
css-color states as tables of prose. It emits **only what a specification
states**: the 818 property names, which 33 of them transitively reach a URL,
which reach a string or a colour, which are stated in prose with no grammar at
all, and the literal keywords each grammar admits.

Which properties a level allows, and which count as overlay, is a judgement and
lives in `properties.mbt` beside the argument for it. `properties_test.mbt` is
where the two meet: every name a level uses must be a real property, the three
lists must be disjoint, and the URL-capable ones are pinned in both directions.

The generation earns its keep immediately. `untrusted_sink_attr` names fourteen
CSS sinks by hand; the specifications name thirty-three. Of the ones a level here
admits, six were missing from the hand-written list — `backdrop-filter`,
`background` (the shorthand containing `background-image`, which IS on the list),
`border-image`, `border-image-source`, `mask-border` and `mask-image`. None was a
live hole, because the `style` attribute was refused wholesale for an untrusted
guest, but "not reachable today" is not "not missing", and reopening it is
exactly what this work does.

Nobody can hold the expansion in their head: `background` → `<bg-layer>#` →
`<bg-image>` → `<image>` → `<url>` → `<url()> | <src()>`.

## Where it runs

| | policy | what changed |
|---|---|---|
| `@setinnerhtml` / `@setinnersvg` (`SafeMarkupFilter`) | `payload()` | was `without_css()` — a blunt drop of both names |
| `@setinnermd` (`MdFilter`, via `filter_for`) | `payload()` | was un-narrowed, with a second sanitizer inside `Build` for HTML blocks |
| `@dangerouslysetinnerhtml` (`MarkupFilter`) | the host's | unchanged; the host's sanitizer decides, as it always did |
| an untrusted guest module (`check_view`) | `payload()` | a CONSTANT `style` or presentation attribute is now read instead of refused by name |
| an app's own tree | opt-in `@filter.CssFilter` | new, and NOT in `Baseline` — see below |

`Sanitizer::attribute_value(name, value, screen?)` is the one call that routes
both shapes: `style` is a declaration list, and an SVG presentation attribute
(`fill`, `stroke`, `stop-color`) is one property's value, asked of the generated
property table rather than of a list here. Any other name comes back unchanged,
so a builder can route every attribute through it without knowing which are which.

### Why `Baseline` does not install `CssFilter`

The payload filters cover the half that matters: each validates the CSS in what
it BUILDS, because nothing runs after a filter on nodes it created. What is left
is an app's own `:style="…"` over application state.

Making that the default would be a behaviour change that costs real pages. Two
things `app()` refuses are ordinary in app-authored CSS: an unquoted
`url(/logo.png)`, for the tokenizer reason above, and `!important`, which is
right for a value somebody else wrote and merely annoying for one the author
wrote. So it is a thing a host adds when it knows its `style` values are not
entirely its own:

```moonbit
app.add_filter(@filter.CssFilter::new(policy=@safecss.CssPolicy::payload()))
```

Order matters and this spelling does not get it: `add_filter` appends behind the
built-in chain, and `CssFilter` rewrites values that `Baseline` reads. It still
validates and still drops there; what it does not get is the URL rule re-reading
a `url()` it rewrote. Putting it in front is `filter_for`'s job — see "Where it
runs" — which is also the only way it will ever be reached by a policy rather
than by a host naming a filter.

## What is left

**The scoped stylesheet.** `Policy::check_style` still accepts a guest's `style`
block unvalidated above the untrusted tier, and `Component::compile_style` still
pastes it into `[data-cid="N"][data-vid="main"]{…}` by string concatenation, so a
`}` escapes the scope. Closing it means parsing selectors and at-rules, keeping
`@media`/`@supports`/`@keyframes`, refusing `@import`/`@font-face`, and
**prefixing each selector with the scope** rather than wrapping the block — which
is what structurally kills the breakout.

It needs escape-aware tokenization, which is the one thing the backslash refusal
above cannot supply: Tailwind emits `.bg-\[\#fff\]` and a selector legitimately
carries escapes. That means either a fix upstream in `mizchi/css` — its
`consume_name` not implementing css-syntax-3 §4.3.7 is a real bug worth sending
back — or a tokenizer here.

**Tailwind bracket syntax.** `has_arbitrary_css` still refuses any `[` or `]` in
a class literal by substring test. The bracket contents are a component value and
could go through the same grammar, which would let a guest write `bg-[#1da1f2]`.
The injection point is the Tailwind compiler's output rather than an attribute,
so it is a different seam from this one.

**A browser differential check.** Every rule here is argued from the
specification and pinned by a unit test. What would raise the confidence further
is feeding a generated corpus through a real `CSSStyleDeclaration` and comparing
the browser's parse to ours — the same move that settled the `java&#9;script:`
question in `docs/sanitizer.md`.
