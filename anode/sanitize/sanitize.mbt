// The compiled sanitizer and the walk it runs.

///|
/// What a config decided about one element's attributes: the compiled form of
/// an `ElementRule`'s two lists.
pub(all) struct ElemAttrs {
  allow : @set.Set[String]?
  remove : @set.Set[String]
}

///|
/// A validated config, in the shape the walk asks questions of.
///
/// Built once. `Sanitizer::check` does set lookups and no allocation per node
/// beyond the path it reports with.
pub struct Sanitizer {
  /// `None` when the config has no element allowlist (a *remove*
  /// configuration): everything not removed is allowed.
  allow_elements : Map[String, ElemAttrs]?
  remove_elements : @set.Set[String]
  replace_with_children : @set.Set[String]
  /// `None` when the config has no global attribute allowlist.
  allow_attributes : @set.Set[String]?
  remove_attributes : @set.Set[String]
  comments : Bool
  data_attributes : Bool
  raw_markup : Bool
  /// A second unconditional overlay, alongside the baseline: how much CSS a
  /// value may carry. See `without_css` and `with_css` for why it is here and
  /// not a config field.
  ///
  /// It was a `Bool` before there was a parser to mean anything more, and
  /// `CssLevel::Deny` is exactly what that `true` meant.
  css : @safecss.CssPolicy
}

///|
/// The framework's own `data-*` attributes, which are never a config's to
/// remove.
///
/// `data-eid` is pushed by `AttrParser::parse_event` and is how a rendered
/// element finds its handler list; `data-cid` / `data-vid` / `data-nid` are
/// stamped by `set_data_attr` during compile. A view sanitized under the
/// spec's default `dataAttributes: false` without this carve-out renders and
/// then does nothing, which is the worst of the available failures — it looks
/// like the component is broken rather than like the host refused it.
///
/// A carve-out rather than an ordering constraint on the pass, so the property
/// holds wherever the pass runs.
pub let reserved_data_attrs : @set.Set[String] = @set.Set::from_array([
  "data-eid", "data-cid", "data-vid", "data-nid",
])

///|
/// An attribute allow/remove list, folded to the case `attribute_allowed`
/// looks names up in.
///
/// A config names attributes in the casing the spec writes them, and for
/// foreign content that casing is camel: `viewBox`, `pathLength`,
/// `preserveAspectRatio`. Folding here rather than preserving case — which is
/// what `normalize_tag` does for ELEMENT names — is deliberate, for two
/// reasons.
///
/// The platform does not distinguish them. An HTML parser ASCII-lowercases
/// every attribute name while tokenizing, and only then maps it back through
/// the fixed "adjust SVG attributes" table; `viewBox`, `viewbox` and `VIEWBOX`
/// in source all reach the DOM as `viewBox`. Case-sensitive matching would
/// refuse a guest whose spelling the browser accepts.
///
/// And unlike elements, no two attributes anywhere in HTML, SVG or MathML
/// differ only by case, so folding cannot merge two distinct names — which
/// means it cannot widen a *remove* list into a case bypass. Preserving case
/// could: a config removing `viewbox` would silently keep `viewBox`.
fn attr_set(names : Array[String]) -> @set.Set[String] {
  @set.Set::from_array(names.map(fn(n) { n.to_lower() }))
}

///|
/// Compile a config, or report every way it contradicts itself.
pub fn Sanitizer::new(cfg : SanitizerConfig) -> Sanitizer raise InvalidConfig {
  let errors = cfg.validate()
  if !errors.is_empty() {
    raise InvalidConfig(errors)
  }
  let allow_elements : Map[String, ElemAttrs]? = match cfg.elements {
    None => None
    Some(rules) => {
      let m : Map[String, ElemAttrs] = Map([])
      for r in rules {
        m[r.elem.key()] = {
          allow: match r.attributes {
            None => None
            Some(names) => Some(attr_set(names))
          },
          remove: match r.remove_attributes {
            None => attr_set([])
            Some(names) => attr_set(names)
          },
        }
      }
      Some(m)
    }
  }
  fn elem_set(names : Array[ElementName]?) -> @set.Set[String] {
    @set.Set::from_array(
      match names {
        None => []
        Some(ns) => ns.map(ElementName::key)
      },
    )
  }

  {
    allow_elements,
    remove_elements: elem_set(cfg.remove_elements),
    replace_with_children: elem_set(cfg.replace_with_children_elements),
    allow_attributes: match cfg.attributes {
      None => None
      Some(names) => Some(attr_set(names))
    },
    remove_attributes: attr_set(cfg.remove_attributes.unwrap_or([])),
    // Absent means KEPT. Dropping comments is something the spec's default
    // CONFIGURATION does, not something its unsafe baseline does — "calling
    // removeUnsafe(), or passing a custom sanitizer to the safe method, only
    // removes the XSS-unsafe items; it does not remove the additional items,
    // comments, and data-* attributes". Conflating the two would refuse an
    // ordinary commented guest view, and would refuse the `Comment` nodes
    // `ANode::parse` synthesizes for its own error paths.
    comments: cfg.comments.unwrap_or(true),
    data_attributes: cfg.data_attributes.unwrap_or(false),
    raw_markup: cfg.raw_markup.unwrap_or(false),
    // A config says nothing about CSS, so the compiled sanitizer takes the
    // permissive answer the `style` attribute has always had. Narrowing is
    // `with_css`, and the callers that render markup they did not write do it
    // on the way in.
    css: @safecss.CssPolicy::app(),
  }
}

///|
/// The same sanitizer with author CSS taken away: no `<style>` element in
/// either namespace, and no `style` attribute anywhere.
///
/// ## Why the safe directives ask for this
///
/// `@setinnerhtml` and `@setinnersvg` promise safety in their names, and the
/// default config is a REMOVE configuration — everything not named is allowed —
/// so under it a payload's `style` survives. CSS is not script, but it is not
/// nothing either: `url(…)` in a presentation property is a request to an
/// origin of the payload's choosing, and `position:fixed;inset:0` over the host
/// page is a click the person thought they were giving to something else.
/// Neither is a thing the sanitizer's vocabulary can talk about, because the
/// Sanitizer API decides NAMES and both of those live in a value.
///
/// `anode/sanitize/css` parses a declaration list and re-emits it rather than
/// approving the author's bytes, so this is not the only answer available. It
/// is kept because it is still the right answer for a host that wants its
/// guests to style with its own classes and nothing else, and because it is
/// what every existing caller of this function asked for.
///
/// What a caller probably wants instead is `with_css`, and in particular
/// `@safecss.CssPolicy::payload()`: level `Computed` so a payload can lay
/// itself out, `overlay` off so it cannot leave its box, and `FragmentOnly` so
/// `fill="url(#grad)"` works and nothing fetches.
///
/// The `<style>` ELEMENT is dropped by both, and stays dropped: a stylesheet is
/// selectors and at-rules as well as declarations, and only the declaration
/// half is built. `tgc/SECURITY.md` §7 has the rest.
///
/// ## Why an overlay and not a config
///
/// The obvious spelling is a `SanitizerConfig` with `remove_elements: [style]`
/// and `remove_attributes: ["style"]`, merged into the host's. It does not
/// work: the spec's validity relation — which `SanitizerConfig::validate`
/// enforces, and which is the reason a config here means what it would mean
/// handed to a real `setHTML()` — does not let `remove_elements` coexist with
/// an `elements` allow-list. So the merge would raise for exactly the hosts
/// that configured most carefully.
///
/// As an overlay it composes with any config, valid or narrow, and it can only
/// ever narrow. It sits beside the baseline in `element_verdict` and
/// `attribute_allowed` because that is the same shape: a rule the config does
/// not get a vote on.
pub fn Sanitizer::without_css(self : Sanitizer) -> Sanitizer {
  { ..self, css: @safecss.CssPolicy::deny(), }
}

///|
/// The same sanitizer, with CSS narrowed to what this policy admits.
///
/// The overlay generalized: `without_css()` is `with_css(CssPolicy::deny())`,
/// and every other level keeps the `style` attribute while deciding its VALUE.
/// The `<style>` element is dropped at every level below the default, because
/// a stylesheet is not a declaration list — see `without_css`.
pub fn Sanitizer::with_css(
  self : Sanitizer,
  policy : @safecss.CssPolicy,
) -> Sanitizer {
  { ..self, css: policy, }
}

///|
/// What a value on this attribute may be, once the name is allowed.
///
/// `None` drops the attribute; `Some(text)` is what to write instead of what
/// the author sent, which for CSS is never the same string. Anything that is
/// not a CSS-valued attribute comes back unchanged, so a caller can route every
/// attribute through it without knowing which are which.
///
/// The two shapes a CSS value arrives in are both here: `style` is a
/// declaration LIST, and an SVG presentation attribute (`fill`, `stroke`,
/// `stop-color`) is a single value for the property of the same name. The
/// second is the one that widens what a payload may carry — those names are
/// refused outright for an untrusted guest today, because a dynamic value could
/// have been a `url()` and nothing could tell.
///
/// URL SCHEMES are decided by `screen`, which the caller supplies, because the
/// rule already exists as `@filter.url_value_allowed` and this package cannot
/// see it — two URL rules that could disagree would be one too many. Its
/// DEFAULT REFUSES, so a caller that forgets it gets `UrlRule::NoUrl`
/// behaviour rather than an unchecked URL.
pub fn Sanitizer::attribute_value(
  self : Sanitizer,
  name : String,
  value : String,
  screen? : (String) -> Bool = _ => false,
) -> String? {
  let attr = name.to_lower()
  if attr == "style" {
    return self.css.declarations(value, screen~).css
  }
  if is_css_presentation_attr(attr) {
    return self.css.value(attr, value, screen~)
  }
  Some(value)
}

///|
/// The attribute names that are a CSS property's value rather than a value of
/// their own.
///
/// SVG presentation attributes: `<circle fill="red">` sets the `fill` PROPERTY,
/// with the same grammar it has in a stylesheet, which is why `fill="url(…)"`
/// is a fetch and `fill="red"` is a colour. The set is every name in
/// `@safecss.css_properties` that an element can also carry as an attribute —
/// asked of the generated table rather than listed here, so a property that
/// becomes a presentation attribute is covered without anyone noticing.
///
/// `style` is deliberately NOT in it: it is a declaration list, not a value,
/// and `attribute_value` routes it separately.
fn is_css_presentation_attr(name : String) -> Bool {
  name != "style" && @safecss.css_properties.contains(name)
}

///|
/// What this sanitizer would do to one element name.
pub(all) enum ElementVerdict {
  Keep
  Drop
  ReplaceWithChildren
} derive(Eq, Debug)

///|
pub fn Sanitizer::element_verdict(
  self : Sanitizer,
  tag : String,
  ns : @anode.Ns?,
) -> ElementVerdict {
  let key = (
    { name: normalize_tag(tag, ns), ns: ElemNs::of_anode(ns), } : ElementName).key()
  // The baseline first, and unconditionally: safety comes from the entry
  // point, not from the config, so a config that allows `script` does not get
  // `script`. See `SanitizerConfig::default`.
  if is_unsafe_element(key) {
    return Drop
  }
  // The second overlay, on the same footing as the baseline: a config that
  // allows `style` does not get `style` when CSS has been taken away. Both
  // namespaces, because `<svg><style>` is a stylesheet like any other.
  if !self.css.stylesheet && key is ("style" | "svg:style") {
    return Drop
  }
  if self.replace_with_children.contains(key) {
    return ReplaceWithChildren
  }
  if self.remove_elements.contains(key) {
    return Drop
  }
  match self.allow_elements {
    // A remove configuration: anything not named is allowed.
    None => Keep
    Some(m) => if m.contains(key) { Keep } else { Drop }
  }
}

///|
/// An HTML tag is matched case-insensitively (a parser lowercases it, but a
/// tree built by hand through `h()` may not have been); foreign content keeps
/// source case, because `linearGradient` and `lineargradient` are different
/// SVG elements.
fn normalize_tag(tag : String, ns : @anode.Ns?) -> String {
  match ns {
    None => tag.to_lower()
    Some(_) => tag
  }
}

///|
/// Whether this attribute survives on an element this sanitizer keeps.
///
/// Order matters and follows the spec: the framework's reserved names first
/// (see `reserved_data_attrs`), then `data-*`, then the per-element rules,
/// then the global ones.
pub fn Sanitizer::attribute_allowed(
  self : Sanitizer,
  tag : String,
  ns : @anode.Ns?,
  name : String,
) -> Bool {
  let name = name.to_lower()
  // The baseline, before anything a config says: an event handler is never
  // allowed, however permissive the config is.
  if is_event_handler_attr(name) {
    return false
  }
  // Beside the baseline, and before the reserved carve-out only because no
  // reserved name is `style`. See `without_css`.
  if self.css.level is Deny && name == "style" {
    return false
  }
  if reserved_data_attrs.contains(name) {
    return true
  }
  if is_data_attr(name) && self.data_attributes {
    return true
  }
  let key = (
    { name: normalize_tag(tag, ns), ns: ElemNs::of_anode(ns), } : ElementName).key()
  let per_elem = match self.allow_elements {
    Some(m) => m.get(key)
    None => None
  }
  if per_elem is Some(rules) {
    if rules.remove.contains(name) {
      return false
    }
    if rules.allow is Some(allow) && allow.contains(name) {
      return true
    }
  }
  if self.remove_attributes.contains(name) {
    return false
  }
  match self.allow_attributes {
    // A remove configuration: anything not removed is allowed.
    None => true
    Some(allow) => allow.contains(name)
  }
}

// ---------------------------------------------------------------------------
// The walk

///|
/// One thing in a tree this sanitizer would not keep.
///
/// Structured rather than a message, because the wording belongs to the
/// caller: `tgc/policy` turns one of these into a `Refusal`, a linter would
/// turn the same one into an advisory line, and the two want different words
/// for it.
pub(all) enum Violation {
  Element(tag~ : String, at~ : String)
  ElementUnwrapped(tag~ : String, at~ : String)
  Attribute(tag~ : String, name~ : String, at~ : String)
  Comment(at~ : String)
  RawMarkup(tag~ : String, at~ : String)
} derive(Eq, Debug)

///|
pub fn Violation::at(self : Violation) -> String {
  match self {
    Element(at~, ..)
    | ElementUnwrapped(at~, ..)
    | Attribute(at~, ..)
    | Comment(at~)
    | RawMarkup(at~, ..) => at
  }
}

///|
pub fn Violation::to_string(self : Violation) -> String {
  match self {
    Element(tag~, at~) => "<\{tag}> is not allowed (at \{at})"
    ElementUnwrapped(tag~, at~) =>
      "<\{tag}> is replaced by its children (at \{at})"
    Attribute(tag~, name~, at~) =>
      "attribute '\{name}' is not allowed on <\{tag}> (at \{at})"
    Comment(at~) => "comments are not allowed (at \{at})"
    RawMarkup(tag~, at~) =>
      "<\{tag}> sets markup directly (@dangerouslysetinnerhtml), which cannot be checked before it renders (at \{at})"
  }
}

///|
/// Everything in this tree the sanitizer would not keep, in document order.
///
/// It REPORTS rather than strips, for two reasons. A bundle whose view is
/// silently trimmed renders wrong and its author gets nothing to read, which is
/// the argument `tgc`'s policy makes everywhere: refuse whole, loudly,
/// rather than degrade. And the tree is
/// shared and mutable — a `MacroCall`'s slots alias what the expansion will
/// contain — so a stripping pass has an aliasing problem this one does not.
///
/// Call it on an UNEXPANDED tree, and check a macro's own raw view where the
/// macro is registered. After expansion a node no longer knows which text it
/// came from, and a host macro's body and a guest's slot content are not the
/// same author at the same trust level. See docs/sanitizer.md.
pub fn Sanitizer::check(
  self : Sanitizer,
  tree : @anode.ANode,
) -> Array[Violation] {
  let out : Array[Violation] = []
  self.visit(tree, [], out)
  out
}

///|
fn path_of(trail : Array[String], tag : String) -> String {
  if trail.is_empty() {
    tag
  } else {
    trail.join(">") + ">" + tag
  }
}

///|
fn Sanitizer::visit(
  self : Sanitizer,
  node : @anode.ANode,
  trail : Array[String],
  out : Array[Violation],
) -> Unit {
  match node {
    Dom(d) => {
      let at = path_of(trail, d.tag)
      match self.element_verdict(d.tag, d.ns) {
        Drop => {
          // The element goes; its attributes and children are moot.
          out.push(Element(tag=d.tag, at~))
          return
        }
        ReplaceWithChildren => out.push(ElementUnwrapped(tag=d.tag, at~))
        Keep => self.check_attrs(d, at, out)
      }
      trail.push(d.tag)
      for child in d.childs {
        self.visit(child, trail, out)
      }
      trail.unsafe_pop() |> ignore
    }
    Comment(_) =>
      if !self.comments {
        out.push(Comment(at=path_of(trail, "#comment")))
      }
    Fragment(d) =>
      for child in d.childs {
        self.visit(child, trail, out)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) => self.visit(d.node, trail, out)
    Slot(d) => self.visit(d.node, trail, out)
    Each(d) => self.visit(d.node, trail, out)
    // A macro call's own body is NOT visited: it is the macro author's text,
    // checked where the macro was registered. Its SLOTS are the caller's own
    // subtrees and are visited here — `ANode::for_each_child` does not reach
    // them, which is why this walk exists rather than reusing that one.
    MacroCall(d) =>
      for _, slot in d.slots {
        self.visit(slot, trail, out)
      }
    Text(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
  }
}

///|
fn Sanitizer::check_attrs(
  self : Sanitizer,
  d : @anode.DomData,
  at : String,
  out : Array[Violation],
) -> Unit {
  fn check_name(name : String) {
    if !self.attribute_allowed(d.tag, d.ns, name) {
      out.push(Attribute(tag=d.tag, name~, at~))
    }
  }

  match d.attrs {
    ConstAttrs(m) =>
      for name, _lit in m {
        check_name(name)
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, ..) | ConstA(name~, ..) => check_name(name)
          If(ia) => check_name(ia.name)
          RawHtml(_) =>
            if !self.raw_markup {
              out.push(RawMarkup(tag=d.tag, at~))
            }
          // `@setinnermd` is never a violation, and that is the whole point of
          // it being a separate construct. `raw_markup` is a permission because
          // a raw-HTML payload reaches the DOM as markup that nothing described
          // — the config has no say over what is in it. A markdown payload has
          // no such route: `vdom/filter/markdown` walks it into nodes and asks
          // THIS config about every element and every attribute value on the
          // way. There is nothing left here to refuse.
          //
          // What a host that wants markdown gone does instead is name the
          // elements it will not have (`remove_elements`, or an `elements`
          // allow-list), which is the same lever it already has over every
          // other node in the tree.
          RawMarkdown(_) => ()
          // `@setinnerhtml` and `@setinnersvg` are the same case as
          // `@setinnermd`, and the reasoning above transfers whole: their
          // payload's only route to the DOM is `@markup.html_nodes` /
          // `@markup.svg_nodes`, which ask THIS config for a verdict on every
          // element and run every attribute value past
          // `@filter.attr_value_allowed`. There is nothing left here to refuse.
          //
          // What makes that true rather than hoped for is the pair of
          // fail-closed branches in `vdom/to_dom.mbt`: an app mounted without a
          // filter renders these EMPTY, so "the builder ran" is not an
          // assumption the pass is making about the host.
          SafeHtml(_) | SafeSvg(_) => ()
        }
      }
  }
}
