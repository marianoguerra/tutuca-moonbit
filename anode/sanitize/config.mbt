// The config model, as the spec defines it, plus the validity relation between
// its fields — which is part of the spec rather than advice, and is what keeps
// a config here meaning the same thing it would mean handed to a real
// `Element.setHTML()`.

///|
/// The namespace an element name is in.
///
/// The spec keys a name by a namespace URI string and defaults it to XHTML.
/// anode has a closed set of three (`DomData.ns : Ns?`, where `None` is HTML),
/// so this is closed too: a config naming a namespace anode cannot express
/// should fail to load rather than silently mean less than it says.
pub(all) enum ElemNs {
  Html
  Svg
  MathML
} derive(Eq, Debug, Hash)

///|
/// The anode spelling of a namespace, as `DomData.ns` carries it.
pub fn ElemNs::of_anode(ns : @anode.Ns?) -> ElemNs {
  match ns {
    None => Html
    Some(Svg) => Svg
    Some(MathML) => MathML
  }
}

///|
/// A namespace-qualified element name (`SanitizerElementNamespace`).
pub(all) struct ElementName {
  name : String
  ns : ElemNs
} derive(Eq, Debug)

///|
/// An element in the HTML namespace. Names are matched case-insensitively
/// here and only here: an HTML parser lowercases them, foreign content keeps
/// source case (`linearGradient`, `foreignObject`) and so is matched exactly.
pub fn html(name : String) -> ElementName {
  { name: name.to_lower(), ns: Html }
}

///|
pub fn svg(name : String) -> ElementName {
  { name, ns: Svg }
}

///|
pub fn mathml(name : String) -> ElementName {
  { name, ns: MathML }
}

///|
/// The key an element is looked up by. Not `Hash` on the struct, because the
/// HTML/foreign casing rule has to be applied on the way in.
fn ElementName::key(self : ElementName) -> String {
  match self.ns {
    Html => self.name
    Svg => "svg:" + self.name
    MathML => "math:" + self.name
  }
}

///|
/// An entry in `elements`: a name, plus the per-element attribute rules the
/// spec attaches to allowed elements ONLY
/// (`SanitizerElementNamespaceWithAttributes`). Entries in `remove_elements`
/// and `replace_with_children_elements` carry none, which is why they are
/// `ElementName` and this is not.
pub(all) struct ElementRule {
  elem : ElementName
  attributes : Array[String]?
  remove_attributes : Array[String]?
} derive(Eq, Debug)

///|
/// A plain allowed element, no per-element attribute rules.
pub fn ElementRule::of(elem : ElementName) -> ElementRule {
  { elem, attributes: None, remove_attributes: None }
}

///|
/// `SanitizerConfig`.
///
/// Every field is `Option` and that is load-bearing: the spec distinguishes an
/// ABSENT `elements` (no allowlist — this is a *remove* configuration) from an
/// EMPTY one (an allowlist that permits nothing). Collapsing the two into `[]`
/// would lose the distinction that decides the whole pass.
///
/// Attribute names have no namespace, unlike the spec's
/// `SanitizerAttributeNamespace`, because anode has nowhere to put one:
/// `AttrItem::Plain(name~ : String, …)` is all a view can express, so
/// `xlink:href` arrives as that literal name. See docs/sanitizer.md.
pub(all) struct SanitizerConfig {
  elements : Array[ElementRule]?
  remove_elements : Array[ElementName]?
  replace_with_children_elements : Array[ElementName]?
  attributes : Array[String]?
  remove_attributes : Array[String]?
  comments : Bool?
  data_attributes : Bool?
  /// NOT in the spec — there is no `innerHTML` attribute for it to be about.
  /// tutuca's `@dangerouslysetinnerhtml` is the one construct in a view whose
  /// content is not described, so it gets a field of its own. Absent means
  /// denied.
  raw_markup : Bool?
} derive(Eq, Debug)

///|
/// The empty config: valid, and allows everything. `{}` is a valid
/// `SanitizerConfig` in the spec too.
pub fn SanitizerConfig::empty() -> SanitizerConfig {
  {
    elements: None,
    remove_elements: None,
    replace_with_children_elements: None,
    attributes: None,
    remove_attributes: None,
    comments: None,
    data_attributes: None,
    raw_markup: None,
  }
}

///|
/// One way a config contradicts itself. Reported rather than raised one at a
/// time, because a config is written once by a host and every mistake in it is
/// worth seeing at once.
pub(all) enum ConfigError {
  /// `elements` with `remove_elements`, or `attributes` with
  /// `remove_attributes`: the spec allows one of each pair, never both.
  BothAllowAndRemove(what~ : String)
  Duplicate(what~ : String, name~ : String)
  /// A name in `replace_with_children_elements` that is also allowed or
  /// removed.
  Overlap(what~ : String, name~ : String)
  ElementBothAttrLists(elem~ : String)
  /// With a global `attributes`, an element's `remove_attributes` may only
  /// narrow it — naming something not globally allowed means nothing.
  ElementAttrNotGlobal(elem~ : String, attr~ : String)
  ElementAttrRepeatsGlobal(elem~ : String, attr~ : String)
  /// With a global `remove_attributes`, an element-level list may not repeat
  /// it.
  ElementAttrRepeatsGlobalRemove(elem~ : String, attr~ : String)
  /// `data_attributes: true` and a `data-*` name in a list: the two say
  /// different things about the same attribute.
  DataAttrListed(name~ : String)
  /// A global `remove_attributes` and `data_attributes` cannot coexist.
  DataAttrsWithGlobalRemove
} derive(Eq, Debug)

///|
pub fn ConfigError::to_string(self : ConfigError) -> String {
  match self {
    BothAllowAndRemove(what~) =>
      "config sets both \{what} and remove_\{what}; the spec allows one or the other"
    Duplicate(what~, name~) => "\{what} lists '\{name}' twice"
    Overlap(what~, name~) =>
      "'\{name}' is in replace_with_children_elements and in \{what}"
    ElementBothAttrLists(elem~) =>
      "element '\{elem}' sets both attributes and remove_attributes"
    ElementAttrNotGlobal(elem~, attr~) =>
      "element '\{elem}' removes '\{attr}', which the global attributes list does not allow"
    ElementAttrRepeatsGlobal(elem~, attr~) =>
      "element '\{elem}' allows '\{attr}', which is already globally allowed"
    ElementAttrRepeatsGlobalRemove(elem~, attr~) =>
      "element '\{elem}' names '\{attr}', which is already globally removed"
    DataAttrListed(name~) =>
      "'\{name}' is listed while data_attributes is true; the two disagree"
    DataAttrsWithGlobalRemove =>
      "data_attributes cannot be set alongside a global remove_attributes"
  }
}

///|
/// A config that does not describe one sanitizer.
///
/// An invalid config is a mistake in the HOST, not something a guest can
/// provoke, so it fails loudly at construction instead of degrading into a
/// sanitizer that quietly permits more than its author meant.
pub suberror InvalidConfig {
  InvalidConfig(Array[ConfigError])
}

///|
pub fn InvalidConfig::to_string(self : InvalidConfig) -> String {
  let InvalidConfig(errors) = self
  errors.map(ConfigError::to_string).join("; ")
}

///|
fn is_data_attr(name : String) -> Bool {
  name is [.. "data-", ..]
}

///|
/// Every way this config contradicts itself, in the order the spec states the
/// rules. Empty means it describes exactly one sanitizer.
pub fn SanitizerConfig::validate(self : SanitizerConfig) -> Array[ConfigError] {
  let out : Array[ConfigError] = []
  if self.elements is Some(_) && self.remove_elements is Some(_) {
    out.push(BothAllowAndRemove(what="elements"))
  }
  if self.attributes is Some(_) && self.remove_attributes is Some(_) {
    out.push(BothAllowAndRemove(what="attributes"))
  }

  // No duplicates in any list.
  fn dup_elems(names : Array[ElementName]?, what : String) -> @set.Set[String] {
    let seen = @set.Set::from_array([])
    if names is Some(ns) {
      for n in ns {
        if !seen.add_and_check(n.key()) {
          out.push(Duplicate(what~, name=n.key()))
        }
      }
    }
    seen
  }

  fn dup_attrs(names : Array[String]?, what : String) -> @set.Set[String] {
    let seen = @set.Set::from_array([])
    if names is Some(ns) {
      for n in ns {
        if !seen.add_and_check(n) {
          out.push(Duplicate(what~, name=n))
        }
      }
    }
    seen
  }

  let allowed_elems = @set.Set::from_array([])
  if self.elements is Some(rules) {
    for r in rules {
      if !allowed_elems.add_and_check(r.elem.key()) {
        out.push(Duplicate(what="elements", name=r.elem.key()))
      }
    }
  }
  let removed_elems = dup_elems(self.remove_elements, "remove_elements")
  let replaced = dup_elems(
    self.replace_with_children_elements,
    "replace_with_children_elements",
  )
  let global_allow = dup_attrs(self.attributes, "attributes")
  let global_remove = dup_attrs(self.remove_attributes, "remove_attributes")

  // replace_with_children_elements is disjoint from both element lists.
  for key in replaced {
    if allowed_elems.contains(key) {
      out.push(Overlap(what="elements", name=key))
    }
    if removed_elems.contains(key) {
      out.push(Overlap(what="remove_elements", name=key))
    }
  }

  // data_attributes interacts with everything.
  let data_attrs = self.data_attributes.unwrap_or(false)
  // DEFINED, not true: with a global remove list the flag has nothing to say
  // either way, and the spec disallows writing it at all rather than letting
  // it read as meaningful.
  if self.data_attributes is Some(_) && self.remove_attributes is Some(_) {
    out.push(DataAttrsWithGlobalRemove)
  }
  if data_attrs {
    for name in global_allow {
      if is_data_attr(name) {
        out.push(DataAttrListed(name~))
      }
    }
    for name in global_remove {
      if is_data_attr(name) {
        out.push(DataAttrListed(name~))
      }
    }
  }

  // Per-element attribute rules, against the global lists.
  if self.elements is Some(rules) {
    for r in rules {
      let elem = r.elem.key()
      if r.attributes is Some(_) && r.remove_attributes is Some(_) {
        out.push(ElementBothAttrLists(elem~))
      }
      if r.attributes is Some(names) {
        let seen = @set.Set::from_array([])
        for attr in names {
          if !seen.add_and_check(attr) {
            out.push(Duplicate(what="element '\{elem}' attributes", name=attr))
          }
          if data_attrs && is_data_attr(attr) {
            out.push(DataAttrListed(name=attr))
          }
          if global_allow.contains(attr) {
            out.push(ElementAttrRepeatsGlobal(elem~, attr~))
          }
          if global_remove.contains(attr) {
            out.push(ElementAttrRepeatsGlobalRemove(elem~, attr~))
          }
        }
      }
      if r.remove_attributes is Some(names) {
        let seen = @set.Set::from_array([])
        for attr in names {
          if !seen.add_and_check(attr) {
            out.push(
              Duplicate(what="element '\{elem}' remove_attributes", name=attr),
            )
          }
          if data_attrs && is_data_attr(attr) {
            out.push(DataAttrListed(name=attr))
          }
          if global_remove.contains(attr) {
            out.push(ElementAttrRepeatsGlobalRemove(elem~, attr~))
          }
          // With a global allowlist, an element may only NARROW it.
          if self.attributes is Some(_) && !global_allow.contains(attr) {
            out.push(ElementAttrNotGlobal(elem~, attr~))
          }
        }
      }
    }
  }
  out
}
