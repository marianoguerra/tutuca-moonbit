///| Blackbox tests over the config model and the walk.
///
/// Two things they are pinning. The spec's validity relation, which is what
/// keeps a config here meaning what it would mean handed to a real
/// `Element.setHTML()`. And the walk, which exists rather than reusing
/// `ANode::for_each_child` because that one does not reach a macro call's
/// slots — see the last test in this file.

///|
fn parsed(html : String) -> @anode.ANode {
  let px = @anode.ParseContext::new()
  @anode.ANode::parse(html, px).unwrap()
}

///|
fn shown(vs : Array[Violation]) -> Array[String] {
  vs.map(Violation::to_string)
}

///|
/// Whatever a config says, the baseline says otherwise. This is the spec's
/// entry-point rule — `setHTML()` applies unsafe removal on top of the config
/// it is handed — and here there is no unsafe entry point at all, so it is
/// unconditional.
test "the baseline holds against a config that allows everything" {
  let s = Sanitizer::default()
  debug_inspect(
    shown(s.check(parsed("<div><script></script><p>ok</p></div>"))),
    content=(
      #|["<script> is not allowed (at div>script)"]
    ),
  )
  // Even naming it in an allowlist does not get it back.
  let permissive = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([
      ElementRule::of(html("div")),
      ElementRule::of(html("script")),
    ]),
  })
  debug_inspect(
    shown(permissive.check(parsed("<div><script></script></div>"))),
    content=(
      #|["<script> is not allowed (at div>script)"]
    ),
  )
}

///|
/// An event handler is a name, so the static pass settles it. It is also the
/// half of the spec's baseline that is a PREDICATE rather than a list, which
/// is why it cannot live in a config's `remove_attributes`.
test "event handlers are refused by name, whatever the config says" {
  let s = Sanitizer::new({
    ..SanitizerConfig::empty(),
    attributes: Some(["onclick", "class"]),
  })
  // The literal form an attacker writes, and the dynamic form. Both are a
  // NAME, which is why the static pass settles them.
  debug_inspect(
    shown(s.check(parsed("<div onclick=\"alert(1)\" class=\"a\"></div>"))),
    content=(
      #|["attribute 'onclick' is not allowed on <div> (at div)"]
    ),
  )
  debug_inspect(
    shown(s.check(parsed("<div :onclick=\".payload\" class=\"a\"></div>"))),
    content=(
      #|["attribute 'onclick' is not allowed on <div> (at div)"]
    ),
  )
  assert_true(is_event_handler_attr("onclick"))
  assert_true(is_event_handler_attr("onafterprint"))
  // `on` alone is not a handler, and nothing else in HTML starts with it.
  assert_false(is_event_handler_attr("on"))
  assert_false(is_event_handler_attr("open"))
}

///|
/// The framework's own stamps are never a config's to remove. Without this
/// carve-out a view sanitized under the spec's default `dataAttributes: false`
/// renders and then does nothing, because `data-eid` is how a rendered element
/// finds its handler list.
test "the reserved data attributes survive dataAttributes: false" {
  // The carve-out only has anything to do under an ALLOWLIST. With no
  // allowlist there is nothing to be absent from — `data_attributes: false`
  // means "not automatically allowed", not "removed", and a remove
  // configuration allows what it does not name. `comments` is not symmetric
  // with it: that one is an explicit boolean and removes either way.
  let s = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([
      ElementRule::of(html("div")),
      ElementRule::of(html("button")),
    ]),
    attributes: Some(["class"]),
  })
  debug_inspect(s.data_attributes, content="false")
  for name in ["data-eid", "data-cid", "data-vid", "data-nid"] {
    assert_true(s.attribute_allowed("div", None, name))
  }
  assert_false(s.attribute_allowed("div", None, "data-anything-else"))
  // A real view: registering an event stamps data-eid, and it survives an
  // allowlist that never mentions it. Without the carve-out this component
  // would render and then not respond to anything.
  debug_inspect(
    shown(s.check(parsed("<button @on.click=\"go\">go</button>"))),
    content="[]",
  )
}

///|
/// An allow configuration removes what it does not name; a remove
/// configuration keeps it. Absent and empty are different, which is why every
/// config field is an Option.
test "allow and remove configurations are not each other's complement" {
  let allow = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([ElementRule::of(html("div"))]),
  })
  debug_inspect(
    shown(allow.check(parsed("<div><span>x</span></div>"))),
    content=(
      #|["<span> is not allowed (at div>span)"]
    ),
  )
  let remove = Sanitizer::new({
    ..SanitizerConfig::empty(),
    remove_elements: Some([html("span")]),
  })
  debug_inspect(
    shown(remove.check(parsed("<div><span>x</span><b>y</b></div>"))),
    content=(
      #|["<span> is not allowed (at div>span)"]
    ),
  )
  // An EMPTY allowlist allows nothing, and is not the same as no allowlist.
  let nothing = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([]),
  })
  debug_inspect(
    shown(nothing.check(parsed("<div></div>"))),
    content=(
      #|["<div> is not allowed (at div)"]
    ),
  )
}

///|
/// Per-element attribute rules attach to `elements` entries only — the spec's
/// `SanitizerElementNamespaceWithAttributes` — and narrow or widen the global
/// list for that element alone.
test "per-element attribute rules" {
  let s = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([
      { elem: html("a"), attributes: Some(["href"]), remove_attributes: None },
      ElementRule::of(html("div")),
    ]),
    attributes: Some(["class"]),
  })
  assert_true(s.attribute_allowed("a", None, "href"))
  assert_true(s.attribute_allowed("a", None, "class"))
  // href is allowed on <a> and nowhere else.
  assert_false(s.attribute_allowed("div", None, "href"))
  assert_true(s.attribute_allowed("div", None, "class"))
}

///|
/// Foreign content keeps source case, HTML does not: `linearGradient` and
/// `lineargradient` are different SVG elements, while `<DIV>` and `<div>` are
/// one.
test "namespaces and the casing rule" {
  let s = Sanitizer::new({
    ..SanitizerConfig::empty(),
    elements: Some([
      ElementRule::of(html("div")),
      ElementRule::of(html("svg")),
      ElementRule::of(svg("linearGradient")),
    ]),
  })
  debug_inspect(s.element_verdict("DIV", None), content="Keep")
  debug_inspect(s.element_verdict("linearGradient", Some(Svg)), content="Keep")
  debug_inspect(s.element_verdict("lineargradient", Some(Svg)), content="Drop")
  // An HTML <use> is not the SVG one the baseline removes.
  debug_inspect(s.element_verdict("use", Some(Svg)), content="Drop")
  debug_inspect(s.element_verdict("use", None), content="Drop") // not allowed, but by the config
}

///|
/// Comments are a node kind, so the config's `comments` flag is decidable
/// statically like everything else about a described view.
/// Absent means KEPT: dropping comments belongs to the spec's default
/// CONFIGURATION, not to its unsafe baseline. The difference is not academic —
/// `ANode::parse` synthesizes `Comment` nodes for its own error paths
/// ("Error: InvalidTagName …", "bad macro: …"), so a baseline that refused
/// comments would turn a guest's typo into a refusal about something else.
test "comments" {
  debug_inspect(
    shown(Sanitizer::default().check(parsed("<div><!-- hi --></div>"))),
    content="[]",
  )
  let drop = Sanitizer::new({
    ..SanitizerConfig::empty(),
    comments: Some(false),
  })
  debug_inspect(
    shown(drop.check(parsed("<div><!-- hi --></div>"))),
    content=(
      #|["comments are not allowed (at div>#comment)"]
    ),
  )
}

///|
/// The refusal `Policy::check_view` implements today, restated as a config
/// field. There is no `innerHTML` attribute for the spec to have an opinion
/// about, so this is tutuca's own extension to the model.
test "raw markup is a config field, denied by default" {
  let s = Sanitizer::default()
  debug_inspect(
    shown(s.check(parsed("<div @dangerouslysetinnerhtml=\".payload\"></div>"))),
    content=(
      #|["<div> sets markup directly (@dangerouslysetinnerhtml), which cannot be checked before it renders (at div)"]
    ),
  )
}

///|
/// The walk this package has, and the one `ANode::for_each_child` does not.
///
/// A macro call's children become `MacroData.slots` (`new_macro_node`), and
/// `for_each_child` reaches neither them nor the unexpanded body — so
/// `has_raw_html`, which is built on it, returns false for this tree and
/// `Policy::check_view` raises no refusal. That is the hole this walk closes;
/// see dyncomp/SECURITY.md §3.
test "a macro call's slots are part of the caller's own view" {
  let tree = parsed(
    "<x:card><div @dangerouslysetinnerhtml=\".payload\"></div></x:card>",
  )
  // What the existing predicate says about the same tree:
  debug_inspect(tree.has_raw_html(), content="false")
  // What this walk says:
  debug_inspect(
    shown(Sanitizer::default().check(tree)),
    content=(
      #|["<div> sets markup directly (@dangerouslysetinnerhtml), which cannot be checked before it renders (at div)"]
    ),
  )
  // A named slot is the same story.
  let named = parsed(
    "<x:card><x:slot name=\"body\"><script></script></x:slot></x:card>",
  )
  debug_inspect(
    shown(Sanitizer::default().check(named)),
    content=(
      #|["<script> is not allowed (at script)"]
    ),
  )
}

///|
/// A macro's BODY is not walked here on purpose: it is the macro author's
/// text, checked where the macro is registered. After expansion a node no
/// longer knows which text it came from, and a host's macro and a guest's call
/// site are not the same author at the same trust level.
test "a macro call's own body is not the caller's to answer for" {
  let tree = parsed("<x:card title=\"hi\"></x:card>")
  debug_inspect(shown(Sanitizer::default().check(tree)), content="[]")
}

// ---------------------------------------------------------------------------
// Held against the spec, not against anyone's memory of it.

///|
/// The baseline was written from a summary once, and the summary dropped SVG's
/// `script`. Element identity is namespace-qualified, so `html("script")` never
/// matched it and this reached the DOM: an SVG `<script>` inserted through the
/// DOM executes.
test "an SVG script is refused" {
  let px = @anode.ParseContext::new()
  let tree = @anode.ANode::parse(
      "<div><svg><script>alert(1)</script></svg></div>",
      px,
    ).unwrap()
  debug_inspect(
    Sanitizer::default().check(tree).map(Violation::to_string),
    content=(
      #|["<script> is not allowed (at div>svg>script)"]
    ),
  )
}

///|
/// Containment rather than equality: everything the spec's baseline removes has
/// to be refused here, and tutuca may refuse more (it refuses `base`, which the
/// spec leaves to the config layer). Regenerate the right-hand side with
/// `node scripts/fetch-sanitizer-defaults.mjs`.
test "the baseline covers everything the spec's baseline removes" {
  fn shown(e : ElementName) -> String {
    match e.ns {
      Html => e.name
      Svg => "svg:" + e.name
      MathML => "math:" + e.name
    }
  }

  let ours = @set.Set::from_array(unsafe_elements.map(shown))
  for e in spec_baseline_removes {
    assert_true(ours.contains(shown(e)))
  }
  // The one deliberate difference, stated so a regen that dropped it would be
  // noticed rather than absorbed.
  let spec = @set.Set::from_array(spec_baseline_removes.map(shown))
  debug_inspect(
    unsafe_elements.map(shown).filter(k => !spec.contains(k)),
    content=(
      #|["base"]
    ),
  )
}

///|
/// The transcribed allow-list is a valid config by the spec's own validity
/// relation — which is not free, since it carries both a global attribute list
/// and per-element ones.
test "the spec's default configuration is valid and usable" {
  let cfg = SanitizerConfig::spec_default()
  debug_inspect(cfg.validate(), content="[]")
  let s = Sanitizer::new(cfg)
  let px = @anode.ParseContext::new()
  // Document content passes.
  let doc = @anode.ANode::parse(
      "<div><p>hi <em>there</em></p><ul><li>a</li></ul></div>",
      px,
    ).unwrap()
  debug_inspect(s.check(doc).map(Violation::to_string), content="[]")
}

///|
/// The reason it is offered and not imposed: the spec's default is for pasting
/// DOCUMENT content, and a tutuca view describes an INTERACTIVE component. A
/// guest with a button is not an unusual guest.
test "the spec's default configuration refuses an ordinary component view" {
  let s = Sanitizer::new(SanitizerConfig::spec_default())
  let px = @anode.ParseContext::new()
  let view = @anode.ANode::parse(
      "<div><button @on.click=\"go\">go</button><input :value=\".q\"></div>",
      px,
    ).unwrap()
  debug_inspect(
    s.check(view).map(Violation::to_string),
    content=(
      #|[
      #|  "<button> is not allowed (at div>button)",
      #|  "<input> is not allowed (at div>input)",
      #|]

    ),
  )
}
