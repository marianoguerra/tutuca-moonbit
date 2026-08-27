// The static half of a render-time rule: which rules can possibly have
// anything to say about this element.
//
// Every rule in `vdom/filter` is two questions — does this attribute's NAME
// concern me, and if so, is this render's VALUE allowed? The second is why the
// filter exists at all: an attribute's value is a `Val` expression until state
// produces it, so nothing before render can decide it. The first is not like
// that. Every attribute name in a view is a literal (`AttrItem` carries
// `name : String` in every variant), so "does this element have an attribute
// this rule could ever refuse" is answerable once, off the tree, and is the
// same answer on every render.
//
// Answering it once is worth doing because the filter's own measurement says
// so: `benchmarks/OPTIMIZATIONS.md` §"What the filter still costs" puts it at
// +4% to +33% on the workloads that rebuild most, and attributes the whole of
// it to "inspecting every attribute of every element that is BUILT". Almost
// every element carries no URL attribute, no `on*` name, no CSS value and no
// markup payload, and pays a scan of its attribute map per render to establish
// that. With this it pays a field read.
//
// It is NOT the skip set that document proposes. That one is per-VIEW, keyed by
// `data-vid`, and turns on whether a static pass validated the view's constants
// — so one dynamic `:style` deoptimizes a whole view, and a plain app, which
// has no static pass at all, gets nothing. This is per-ELEMENT, and it is only
// about NAMES: nothing here says a value was checked, so the two ideas compose
// rather than compete.

///|
/// Which render-time rules an element's attributes could concern.
///
/// A conservative summary: a `true` means "a rule of this kind may have
/// something to decide here", never that anything is wrong. A `false` is a
/// promise, and the only promise made is about NAMES — that no attribute on
/// this element carries a name the rule would look at. Whether a value is
/// allowed is still the filter's to decide, on every render, for every name
/// that is here.
///
/// The four kinds are the four rules that exist, not a general mechanism: a
/// host's own filter gets `filter_elem` and sees everything, because nothing
/// here could describe what it looks for.
pub(all) struct SinkHints {
  /// A name in `@filter.url_attrs` — `href`, `src`, `srcset`, …
  url : Bool
  /// An `on*` event-handler content attribute.
  handler : Bool
  /// `style`, or an SVG presentation attribute, which is a CSS property's
  /// value under the property's own name.
  css : Bool
  /// One of the four markup payloads (`@dangerouslysetinnerhtml`,
  /// `@setinnerhtml`, `@setinnersvg`, `@setinnermd`), whose filter REPLACES the
  /// element's children with nodes it builds and sanitizes itself.
  markup : Bool
} derive(Eq, Debug)

///|
/// Every rule may have something to decide: the answer when nobody has looked.
///
/// The default everywhere it is not known, and the reason a missing hint is a
/// missed optimization rather than a hole. An element built by hand through
/// `@vdom.h`, or by a markup filter out of a payload, never went through the
/// walk that computes these — so it gets this, and every rule inspects it as it
/// always did.
pub fn SinkHints::all() -> SinkHints {
  { url: true, handler: true, css: true, markup: true, }
}

///|
/// Nothing for any rule to look at. The starting point of the fold, and the
/// answer for the overwhelming majority of elements.
pub fn SinkHints::empty() -> SinkHints {
  { url: false, handler: false, css: false, markup: false, }
}

///|
/// Whether any rule has something to look at.
///
/// What a filter composing several rules — `Baseline`, `Chain` — tests before
/// doing anything at all.
pub fn SinkHints::any(self : SinkHints) -> Bool {
  self.url || self.handler || self.css || self.markup
}
