// Which properties each level admits, and which of them can overlay the page.
//
// This is the POLICY half. `properties_gen.mbt` beside it is the FACT half —
// generated from the specifications, and stating only what a specification
// states. Nothing here is derivable from a spec: no document says whether
// `margin` belongs in a small subset or a large one, and none says that
// `position` is how a payload covers the page it was pasted into. So these
// lists are written by hand, each with the argument for it, and
// `properties_test.mbt` holds every name in them against `css_properties` so a
// typo or a renamed property fails a test rather than silently admitting or
// refusing something.
//
// The direction that matters is the permissive one, and there is a test for it
// too: every name admitted here that appears in the generated `url_properties`
// must reach the `UrlRule`, which it does because `url()` is judged where it
// appears rather than by which property carries it.

///|
/// Level `Constant`: paint and typography, and nothing that computes.
///
/// The question each entry answers is "can this change what a person sees,
/// without changing where anything is". Colour, weight, size, alignment,
/// decoration. Nothing here can move an element, size a box, fetch anything, or
/// contain a function — at this level the value grammar admits no function
/// token at all, so the property list is not the only thing holding the line.
///
/// The list is short on purpose. It is what a comment body, a CMS field, an
/// LLM's markdown or an SVG icon actually uses, and a host that wants no more
/// than that should be able to say so and get a subset small enough to read.
pub let constant_properties : @set.Set[String] = @set.Set::from_array([
  // Colour and paint.
  "color", "opacity", "background-color", "accent-color", "caret-color", "forced-color-adjust",
  "print-color-adjust",
  // SVG paint. `fill` and `stroke` reach `<url>` for a paint server, which is
  // what `UrlRule::FragmentOnly` is for — the value rule decides, not this list.
   "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width",
  "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
  "paint-order", "vector-effect", "stop-color", "stop-opacity", "flood-color", "flood-opacity",
  "lighting-color", "color-interpolation", "color-interpolation-filters", "shape-rendering",
  "text-rendering", "image-rendering",
  // Type.
   "font-size", "font-weight", "font-style", "font-variant", "font-stretch", "font-size-adjust",
  "font-synthesis", "font-kerning", "line-height", "letter-spacing", "word-spacing",
  "text-align", "text-align-last", "text-transform", "text-indent", "text-decoration",
  "text-decoration-line", "text-decoration-style", "text-decoration-color", "text-decoration-thickness",
  "text-underline-offset", "text-underline-position", "text-emphasis", "text-emphasis-color",
  "text-emphasis-style", "vertical-align", "white-space", "white-space-collapse",
  "text-wrap", "text-wrap-mode", "text-wrap-style", "word-break", "line-break", "overflow-wrap",
  "hyphens", "tab-size", "direction", "unicode-bidi", "writing-mode", "text-orientation",
  "font-variant-caps", "font-variant-numeric", "font-variant-ligatures",
  // Borders and rules, which are paint on the edge of a box rather than a box.
   "border-color", "border-style", "border-width", "border-top-color", "border-top-style",
  "border-top-width", "border-right-color", "border-right-style", "border-right-width",
  "border-bottom-color", "border-bottom-style", "border-bottom-width", "border-left-color",
  "border-left-style", "border-left-width", "border-radius", "border-top-left-radius",
  "border-top-right-radius", "border-bottom-left-radius", "border-bottom-right-radius",
  "outline-color", "outline-style", "outline-width", "outline-offset",
  // Lists and visibility.
   "list-style-type", "list-style-position", "visibility",
])

///|
/// Level `Computed` adds layout, the box, and the properties whose values are
/// worth a function.
///
/// The argument for admitting layout at all: a payload that cannot size or
/// arrange itself is not a payload anyone can use, and laying yourself out
/// inside the box you were given harms nobody. What DOES harm somebody is
/// leaving that box, which is `overlay_properties` and a separate switch.
///
/// `background` and `list-style` are in here as shorthands even though both can
/// carry an image, for the same reason `fill` is in `constant_properties`: the
/// `url()` inside them is judged by `UrlRule` at the point it appears. Refusing
/// the property outright would lose `background: #fff` and `list-style: none`,
/// which is a lot of ordinary CSS for no safety at all.
pub let computed_properties : @set.Set[String] = @set.Set::from_array([
  // The box.
  "display", "box-sizing", "width", "height", "min-width", "min-height", "max-width",
  "max-height", "inline-size", "block-size", "min-inline-size", "min-block-size",
  "max-inline-size", "max-block-size", "aspect-ratio", "margin", "margin-top", "margin-right",
  "margin-bottom", "margin-left", "margin-block", "margin-block-start", "margin-block-end",
  "margin-inline", "margin-inline-start", "margin-inline-end", "padding", "padding-top",
  "padding-right", "padding-bottom", "padding-left", "padding-block", "padding-block-start",
  "padding-block-end", "padding-inline", "padding-inline-start", "padding-inline-end",
  "border", "border-top", "border-right", "border-bottom", "border-left", "border-block",
  "border-inline", "outline", "overflow", "overflow-x", "overflow-y", "overflow-block",
  "overflow-inline", "text-overflow", "resize",
  // Flow.
   "float", "clear", "flex", "flex-basis", "flex-direction", "flex-flow", "flex-grow",
  "flex-shrink", "flex-wrap", "order", "align-content", "align-items", "align-self",
  "justify-content", "justify-items", "justify-self", "place-content", "place-items",
  "place-self", "gap", "row-gap", "column-gap", "grid", "grid-area", "grid-auto-columns",
  "grid-auto-flow", "grid-auto-rows", "grid-column", "grid-column-end", "grid-column-start",
  "grid-row", "grid-row-end", "grid-row-start", "grid-template", "grid-template-columns",
  "grid-template-rows", "columns", "column-count", "column-width", "column-gap",
  "column-rule", "column-rule-color", "column-rule-style", "column-rule-width", "column-span",
  // Tables.
   "border-collapse", "border-spacing", "caption-side", "empty-cells", "table-layout",
  // Type that wants a string or a function.
   "font-family", "font-feature-settings", "font-variation-settings", "line-clamp",
  // Background painting, minus the shorthand's positioning of a fetched image
  // — which is `UrlRule`'s call, not this list's.
   "background", "background-image", "background-clip", "background-origin", "background-repeat",
  "background-size", "background-position", "background-position-x", "background-position-y",
  "background-attachment", "border-image", "border-image-source", "border-image-slice",
  "border-image-width", "border-image-outset", "border-image-repeat",
  // Replaced content and lists.
   "object-fit", "object-position", "list-style", "list-style-image",
  // Interaction that does not move anything.
   "cursor", "user-select", "touch-action", "scroll-behavior", "overscroll-behavior",
  "scrollbar-color", "scrollbar-gutter", "scrollbar-width",
  // SVG geometry, which is the shape of the element and not where it sits.
   "cx", "cy", "r", "rx", "ry", "x", "y", "d", "clip-rule", "marker", "marker-start",
  "marker-mid", "marker-end", "dominant-baseline", "alignment-baseline", "baseline-shift",
  "text-anchor", "mask-type",
])

///|
/// The properties that can put content over the page around it.
///
/// Gated by `CssPolicy::overlay`, at every level, because the risk is not
/// script and no scheme check sees it. A `position:fixed; inset:0` element with
/// `opacity:0` is an invisible sheet over the whole page and every click on it
/// belongs to whoever wrote the payload; a `transform: translate(-100px)` walks
/// out of the box a host measured for it; a `z-index` puts it on top of the
/// host's own chrome.
///
/// Three that read as surprising:
///
/// - `box-shadow` and `text-shadow` paint OUTSIDE the element's own box. They
///   cannot capture a click, so this is spoofing rather than clickjacking — but
///   a shadow the size of the viewport is a grey sheet over the page, and the
///   property costs nothing to gate.
/// - `filter` and `backdrop-filter` reach outside too (`drop-shadow`), and
///   `backdrop-filter` renders what is BEHIND the element, which is content the
///   payload's author was not shown.
/// - `mask` and `clip-path` are here rather than in the paint list because a
///   mask is how you make a large click target invisible while keeping it.
pub let overlay_properties : @set.Set[String] = @set.Set::from_array([
  "position", "top", "right", "bottom", "left", "inset", "inset-block", "inset-block-start",
  "inset-block-end", "inset-inline", "inset-inline-start", "inset-inline-end", "z-index",
  "transform", "transform-origin", "transform-box", "transform-style", "translate",
  "rotate", "scale", "perspective", "perspective-origin", "pointer-events", "mix-blend-mode",
  "background-blend-mode", "isolation", "box-shadow", "text-shadow", "filter", "backdrop-filter",
  "clip-path", "clip", "mask", "mask-image", "mask-clip", "mask-composite", "mask-mode",
  "mask-origin", "mask-position", "mask-repeat", "mask-size", "mask-border", "will-change",
  "contain", "content-visibility", "view-transition-name",
])

///|
/// Whether this policy admits this property at all, and why not when it does
/// not.
///
/// Order is load-bearing in one place: `overlay` is asked BEFORE the level, so
/// a host that turned overlay off gets `Overlay` as the reason rather than
/// `UnknownProperty`. The two are not the same message to a person trying to
/// find out why their styling vanished.
fn property_verdict(
  property : String,
  policy : CssPolicy,
) -> Result[Unit, CssReason] {
  if policy.level is Deny {
    return Err(UnknownProperty)
  }
  if overlay_properties.contains(property) {
    return if policy.overlay { Ok(()) } else { Err(Overlay) }
  }
  if constant_properties.contains(property) {
    return Ok(())
  }
  if policy.level is Computed && computed_properties.contains(property) {
    return Ok(())
  }
  Err(UnknownProperty)
}

///|
/// The generated keyword table, as a lookup.
///
/// Built once from `keyword_rows` rather than emitted as a `Map` literal, so
/// the generated file stays one readable line per property.
pub let property_keywords : Map[String, @set.Set[String]] = {
  let out : Map[String, @set.Set[String]] = Map([])
  for row in keyword_rows {
    let words : @set.Set[String] = Set([])
    let buf = StringBuilder()
    fn flush() {
      let w = buf.to_string()
      if w != "" {
        words.add(w)
      }
      buf.reset()
    }

    for c in row.1 {
      if c == ' ' {
        flush()
      } else {
        buf.write_char(c)
      }
    }
    flush()
    out[row.0] = words
  }
  out
}

///|
/// Whether level `Constant` admits this bare identifier on this property.
///
/// Only `Constant` asks. The generated table is CSS CORRECTNESS rather than
/// safety — an identifier cannot fetch, execute or move anything, so a wrong
/// answer here refuses valid styling and never admits an attack. That is
/// exactly the trade `Constant` is for: a subset small enough that a host can
/// say what is in it. `Computed` relaxes it, because the table unions grammars
/// across every level of every spec and still cannot know about the vendor
/// keyword a real page uses.
fn constant_keyword_ok(property : String, ident : String) -> Bool {
  if css_wide_keywords.contains(ident) {
    return true
  }
  if color_properties.contains(property) && named_colors.contains(ident) {
    return true
  }
  match property_keywords.get(property) {
    Some(words) => words.contains(ident)
    // A property with no keyword row takes no bare identifier: its grammar is
    // numbers and types all the way down.
    None => false
  }
}
