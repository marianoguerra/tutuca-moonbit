// The hand-written policy, held against the generated facts.
//
// `properties.mbt` is a judgement and `properties_gen.mbt` is what the
// specifications say. Neither can check the other on its own; these tests are
// where they meet.

///|
/// Level `Constant`, for the keyword table's own tests.
fn kept_at_constant(src : String) -> String {
  let policy : @css.CssPolicy = {
    level: Constant,
    overlay: false,
    url: NoUrl,
    stylesheet: false,
  }
  match policy.declarations(src).css {
    Some(text) => text
    None => "-"
  }
}

///|
/// Lexicographic order, character by character.
///
/// `String`'s own `Compare` orders by LENGTH first, which is a fine total order
/// and an unreadable one for a pinned list of property names: it would put
/// `stop-color` before `font-stretch`. These lists exist to be read in a diff.
fn lex(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let x = a.unsafe_get(i).to_int()
    let y = b.unsafe_get(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// A set as one sorted line.
fn line(names : Array[String]) -> String {
  names.sort_by((a, b) => lex(a, b))
  names.join(" ")
}

///|
/// The names in a set that are not in another, sorted, as one line.
fn missing(from : @set.Set[String], present : @set.Set[String]) -> String {
  let out : Array[String] = []
  for name in from {
    if !present.contains(name) {
      out.push(name)
    }
  }
  line(out)
}

///|
/// Every property any level names must be a property some specification
/// defines.
///
/// This is the cheap half and it earns its keep anyway: a typo in a
/// hand-written allow-list is invisible in both directions — a misspelled entry
/// in a level list silently refuses valid styling, and one in the overlay list
/// silently admits an overlay. Neither shows up in any other test, because
/// nothing else ever asks whether the name is real.
test "every property a level names is a real property" {
  inspect(missing(@css.constant_properties, @css.css_properties), content="")
  inspect(missing(@css.computed_properties, @css.css_properties), content="")
  inspect(missing(@css.overlay_properties, @css.css_properties), content="")
}

///|
/// The levels do not overlap each other, and neither overlaps the overlay set.
///
/// `property_verdict` asks `overlay` first, so an entry in both would be gated
/// by the switch and never reachable from its level — which is a silently
/// narrower subset than the list says. Better to fail here.
test "the three lists are disjoint" {
  let shared : Array[String] = []
  for name in @css.constant_properties {
    if @css.computed_properties.contains(name) ||
      @css.overlay_properties.contains(name) {
      shared.push(name)
    }
  }
  for name in @css.computed_properties {
    if @css.overlay_properties.contains(name) {
      shared.push(name)
    }
  }
  inspect(line(shared), content="")
}

///|
/// The URL-capable properties an admitted level carries, for the record.
///
/// A property in here is one where `UrlRule` is load-bearing: the level admits
/// the property and the specification says its value can reach a `<url>`, so
/// the only thing between a payload and a fetch is the value rule. Pinning the
/// list means a specification change that turns an innocuous property into a
/// URL sink — which has happened, `cursor` and `list-style` both gained one —
/// shows up as a failing test rather than as nothing at all.
test "which admitted properties depend on the UrlRule" {
  let out : Array[String] = []
  for name in @css.url_properties {
    if @css.constant_properties.contains(name) ||
      @css.computed_properties.contains(name) ||
      @css.overlay_properties.contains(name) {
      out.push(name)
    }
  }
  inspect(
    line(out),
    content=(
      #|backdrop-filter background background-image border-image border-image-source clip-path cursor fill filter list-style list-style-image marker marker-end marker-mid marker-start mask mask-border mask-image stroke
    ),
  )
}

///|
/// And the ones no level admits at all, which is the other half of the same
/// answer.
test "the URL sinks no level admits" {
  let out : Array[String] = []
  for name in @css.url_properties {
    if !(@css.constant_properties.contains(name) ||
      @css.computed_properties.contains(name) ||
      @css.overlay_properties.contains(name)) {
      out.push(name)
    }
  }
  inspect(
    line(out),
    content=(
      #|background-tbd bookmark-label content cue cue-after cue-before fill-image mask-border-source offset offset-path shape-inside shape-outside string-set stroke-image
    ),
  )
}

///|
/// What the generated table found that the hand-written list in
/// `tgc/policy/view_authority.mbt` does not have.
///
/// That list is the one this work exists to replace, and it is worth stating
/// what it cost to write by hand. `untrusted_sink_attr` names fourteen CSS
/// sinks; the specifications name thirty-three, and the six below are ones a
/// person would have to have read sixty specs to find. None of them was a live
/// hole — the `style` attribute is refused wholesale for an untrusted guest, so
/// there was no way to reach any of them — but "not reachable today" is not the
/// same as "not missing", and the next tier is exactly the one that would have
/// reached them.
///
/// `background` is the one to notice: the hand-written list has
/// `background-image` and not the shorthand that contains it.
test "the misses in the hand-written sink list" {
  let by_hand : @set.Set[String] = @set.Set::from_array([
    "background-image", "clip-path", "cursor", "fill", "filter", "list-style", "list-style-image",
    "marker", "marker-end", "marker-mid", "marker-start", "mask", "stroke",
  ])
  // Only the ones a level here admits: the rest are refused by name anyway, so
  // they were never the interesting half.
  let out : Array[String] = []
  for name in @css.url_properties {
    let admitted = @css.constant_properties.contains(name) ||
      @css.computed_properties.contains(name) ||
      @css.overlay_properties.contains(name)
    if admitted && !by_hand.contains(name) {
      out.push(name)
    }
  }
  inspect(
    line(out),
    content=(
      #|backdrop-filter background border-image border-image-source mask-border mask-image
    ),
  )
}

///|
/// The keyword table is only consulted at `Constant`, and this is what it looks
/// like when it is.
///
/// It comes from the specifications, so it carries what a specification says
/// and not what a person remembers. `text-align` has eight keywords across
/// css-text-3 and -4, including `match-parent` and `justify-all`, which a
/// hand-written list would have had four of.
test "the generated keyword table is what Constant checks against" {
  let words = @css.property_keywords.get("text-align").unwrap().to_array()
  inspect(
    line(words),
    content="center end justify justify-all left match-parent right start",
  )
  // A property whose grammar is types all the way down has no row, and so takes
  // no bare identifier at all at this level — only a CSS-wide keyword, which
  // `constant_keyword_ok` answers before it looks anything up.
  inspect(@css.property_keywords.get("opacity") is None, content="true")
  inspect(kept_at_constant("opacity:0.5"), content="opacity:0.5")
  inspect(kept_at_constant("opacity:inherit"), content="opacity:inherit")
  inspect(kept_at_constant("opacity:none"), content="-")
}

///|
/// Colour keywords are shared rather than copied onto every colour property.
///
/// 148 named colours plus the system colours, on each of the 55 properties that
/// take a `<color>`, would be most of the generated file. The expansion stops
/// at `<color>` and `constant_keyword_ok` consults `@css.named_colors` instead.
test "colour keywords live in one place" {
  inspect(@css.named_colors.contains("rebeccapurple"), content="true")
  inspect(@css.named_colors.contains("canvastext"), content="true")
  inspect(@css.named_colors.contains("transparent"), content="true")
  inspect(@css.color_properties.contains("fill"), content="true")
  // And they are NOT duplicated into the per-property rows.
  inspect(
    @css.property_keywords.get("color") is None ||
    !@css.property_keywords.get("color").unwrap().contains("rebeccapurple"),
    content="true",
  )
}
