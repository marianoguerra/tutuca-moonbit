// What a caller asks for, and what it gets told was dropped.

///|
/// How much CSS a validator admits, smallest first.
///
/// The levels are ordered and each is a superset of the one before it. They
/// order by EXPRESSIVENESS, not by risk: the two things that carry risk —
/// leaving your box, and fetching a URL — are switches on `CssPolicy` rather
/// than points on this line, because a host that wants a guest to lay itself
/// out is not thereby a host that wants it to reach the network.
pub(all) enum CssLevel {
  /// No CSS at all. What `Sanitizer::without_css` meant before there was a
  /// parser to mean anything else, and still the right answer for a host that
  /// wants its guests to style with its own classes.
  Deny
  /// Paint and typography, with no function anywhere in a value.
  ///
  /// Colours, lengths, percentages and per-property keywords. No `rgb()`, no
  /// `calc()`, no `var()`, no strings, no custom properties, no layout. It is a
  /// small subset on purpose: it covers a comment body, a CMS field, an SVG
  /// icon's `fill` and `stroke`, and the `text-align` a GFM table writes, and
  /// nothing in it can compute, position, overlay or fetch.
  Constant
  /// Level `Constant`, plus layout and a closed set of functions.
  ///
  /// The box properties, flex and grid, the colour functions, `calc()` and its
  /// siblings, the gradients, the easings, and `var()` over custom properties
  /// validated by the same grammar. Still no `url()` and still no at-rule.
  Computed
} derive(Eq, Debug)

///|
/// What may appear inside `url()`, when a level would otherwise admit the
/// property carrying it.
///
/// Separate from the level because egress is a different question from
/// expressiveness, and a host answers it from what it knows about the author
/// rather than from how much CSS the author needs.
pub(all) enum UrlRule {
  /// No `url()`, and no property that can reach one. The default at every
  /// level.
  NoUrl
  /// `url(#name)` and nothing else.
  ///
  /// A fragment-only reference fetches nothing — it names an element in the
  /// document that is already there. It is also the difference between an SVG
  /// subset that is worth having and one that is not: `fill`, `stroke`,
  /// `clip-path`, `mask` and `marker-*` are how SVG points at a gradient or a
  /// filter it defined itself, and refusing them refuses ordinary artwork.
  FragmentOnly
  /// `url(#name)`, plus any absolute or relative URL whose scheme the caller
  /// has approved.
  ///
  /// The scheme rule is NOT reimplemented here. The caller passes it in as
  /// `screen` — `@filter.url_value_allowed` for an app, and the origin pinning
  /// in `external_url.mbt` on top of it for a guest — because two URL rules
  /// that could disagree would be one too many.
  ///
  /// `screen` DEFAULTS TO REFUSING, so asking for `Screened` and passing
  /// nothing behaves as `NoUrl` rather than as no check at all.
  Screened
} derive(Eq, Debug)

///|
/// A level and the two switches, which together are everything a caller says.
pub(all) struct CssPolicy {
  level : CssLevel
  /// Whether to admit the properties that can move content out of the box the
  /// page gave it: `position`, `z-index`, the transforms, `pointer-events` and
  /// the rest of `overlay_properties`.
  ///
  /// Off is the safe answer for content the page's author did not write, and it
  /// is about clickjacking rather than about script: a `position:fixed;inset:0`
  /// element with `opacity:0` is an invisible sheet over the whole page, and
  /// every click on it belongs to whoever wrote the payload. No amount of
  /// scheme checking sees that, which is why it is its own switch.
  overlay : Bool
  url : UrlRule
  /// Whether a `<style>` ELEMENT survives.
  ///
  /// A separate question from every other one here, because a stylesheet is not
  /// a declaration list: it is selectors and at-rules as well, and only the
  /// declaration half is built. A `<style>` block a host did not write can name
  /// `html`, `:root` or `body` and restyle the page around it, which no amount
  /// of value checking sees.
  ///
  /// True for a page's own tree and false for anything else. `Policy::check_style`
  /// and `Component::compile_style` are the other half of this, and are still
  /// the string-concatenation they always were — `dyncomp/SECURITY.md` §4.
  stylesheet : Bool
} derive(Eq, Debug)

///|
/// No CSS. Today's `without_css`, as a level.
pub fn CssPolicy::deny() -> CssPolicy {
  { level: Deny, overlay: false, url: NoUrl, stylesheet: false }
}

///|
/// For a value somebody else wrote: a sanitized markup payload, a markdown
/// document, an untrusted guest's view.
///
/// `Computed` so the payload can lay itself out, no overlay so it cannot leave
/// its box, and `FragmentOnly` so SVG artwork works and nothing fetches.
pub fn CssPolicy::payload() -> CssPolicy {
  { level: Computed, overlay: false, url: FragmentOnly, stylesheet: false }
}

///|
/// For a value the page's own author wrote.
///
/// Everything `Computed` has, including the overlay properties, and `url()`
/// screened by the caller's existing scheme rule. This is what an ordinary app
/// gets: it keeps `position:absolute` and `background-image:url(/logo.png)`
/// working while still refusing `background-image:url(javascript:…)` and
/// anything the tokenizer could not make sense of.
pub fn CssPolicy::app() -> CssPolicy {
  { level: Computed, overlay: true, url: Screened, stylesheet: true }
}

///|
/// Why one declaration did not survive.
///
/// Structured rather than a message, for the reason `Violation` is: `@filter`
/// turns one into a `Dropped` a host drains, `dyncomp/policy` would turn the
/// same one into a `Refusal`, and the wording belongs to whoever is speaking.
pub(all) enum CssReason {
  /// The tokenizer, the normalization phase, or the declaration splitter said
  /// no before any rule got a look. Carries what tripped it.
  Malformed(String)
  /// A backslash. See `normalize.mbt` — the reason this is its own answer and
  /// not `Malformed` is that it is the one refusal a reader will think is a bug.
  Escape
  /// No specification defines this property, or no level admits it.
  UnknownProperty
  /// A token, unit, keyword or function argument the level does not admit.
  BadValue(String)
  /// A function the level does not admit, by name.
  Function(String)
  /// A `url()`, under a `UrlRule` that does not allow this one.
  Url(String)
  /// `!important`.
  Important
  /// A property that can move content out of its box, with `overlay` off.
  Overlay
  /// More declarations, tokens or nesting than the caps allow.
  TooLarge
} derive(Eq, Debug)

///|
/// One dropped declaration.
pub(all) struct CssDrop {
  /// The property, lowercased; `""` when the drop happened before a property
  /// name was read.
  property : String
  reason : CssReason
} derive(Eq, Debug)

///|
/// A one-line rendering, for a report a person reads.
pub fn CssDrop::to_string(self : CssDrop) -> String {
  let what = if self.property == "" { "declaration" } else { self.property }
  match self.reason {
    Malformed(why) => "\{what}: malformed (\{why})"
    Escape => "\{what}: a backslash escape, which no level admits"
    UnknownProperty => "\{what}: not a property this level admits"
    BadValue(tok) => "\{what}: value not admitted (\{tok})"
    Function(name) => "\{what}: \{name}() is not admitted"
    Url(target) => "\{what}: url(\{target}) is not admitted"
    Important => "\{what}: !important is not admitted"
    Overlay => "\{what}: can overlay the page, and overlay is off"
    TooLarge => "\{what}: over a size cap"
  }
}

///|
/// The result of validating one declaration list: what survived, canonically
/// re-emitted, and everything that did not.
pub(all) struct CssResult {
  /// The canonical declaration list, or `None` when nothing survived.
  ///
  /// Never a substring of the input. See `emit.mbt`.
  css : String?
  dropped : Array[CssDrop]
  /// Every non-fragment `url()` target that survived under `Screened`, in
  /// source order.
  ///
  /// A record of what the caller's own `screen` admitted, for a report — not a
  /// list of things still to check. Nothing reaches `css` without having passed
  /// `screen` already. Empty under `NoUrl` and `FragmentOnly`, which settle the
  /// question without asking.
  screened_urls : Array[String]
} derive(Eq, Debug)

///|
/// Caps, so a pathological value costs bounded time rather than a frozen tab.
///
/// Generous by design, in the same register as `Policy::check_quotas`: they
/// catch a runaway, not an author. A `style` attribute with 128 declarations is
/// already not something a person wrote.
pub let max_declarations : Int = 128

///|
pub let max_tokens : Int = 4096

///|
/// How deep functions may nest. `calc(1px + calc(2px * (3 + 4)))` is 3.
pub let max_nesting : Int = 8
