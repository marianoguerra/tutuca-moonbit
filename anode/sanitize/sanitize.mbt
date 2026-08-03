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
            Some(names) => Some(@set.Set::from_array(names))
          },
          remove: match r.remove_attributes {
            None => @set.Set::from_array([])
            Some(names) => @set.Set::from_array(names)
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
      Some(names) => Some(@set.Set::from_array(names))
    },
    remove_attributes: @set.Set::from_array(cfg.remove_attributes.unwrap_or([])),
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
  }
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
    { name: normalize_tag(tag, ns), ns: ElemNs::of_anode(ns) } : ElementName).key()
  // The baseline first, and unconditionally: safety comes from the entry
  // point, not from the config, so a config that allows `script` does not get
  // `script`. See `SanitizerConfig::default`.
  if is_unsafe_element(key) {
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
  if reserved_data_attrs.contains(name) {
    return true
  }
  if is_data_attr(name) && self.data_attributes {
    return true
  }
  let key = (
    { name: normalize_tag(tag, ns), ns: ElemNs::of_anode(ns) } : ElementName).key()
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
/// caller: `dyncomp/policy` turns one of these into a `Refusal`, a linter would
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
/// the same argument `dyncomp` already made about capabilities. And the tree is
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
        }
      }
  }
}
