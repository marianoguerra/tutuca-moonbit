///|
pub fn text(s : String) -> Vdom {
  Text(s)
}

///|
pub fn comment(s : String) -> Vdom {
  Comment(s)
}

///|
/// Fragments splice into their parent's child list at construction time, so
/// a normalized tree never contains a Fragment as a child — only as a root.
/// (Port of the JS `addChild` flattening; MoonBit children are already all
/// `Vdom`, so only the fragment-splicing part remains.)
fn normalize_childs(childs : Array[Vdom]) -> Array[Vdom] {
  let out : Array[Vdom] = []
  for child in childs {
    match child {
      Fragment(cs) => out.append(cs)
      c => out.push(c)
    }
  }
  out
}

///|
pub fn fragment(childs : Array[Vdom]) -> Vdom {
  Fragment(normalize_childs(childs))
}

///|
/// Hyperscript constructor.
///
/// - `key` / `ns` are labeled arguments, but `"key"` / `"namespace"` entries
///   in `attrs` are also extracted (labeled argument wins) so tree builders
///   that produce plain attribute maps keep working.
/// - When no namespace is given, `"svg"` / `"math"` tags auto-select their
///   namespace so callers don't thread it by hand; children inherit it at
///   render time.
/// - All-lowercase HTML tags are uppercased for cheap identity comparisons;
///   mixed-case tags (`linearGradient`, `foreignObject`) are preserved so
///   they render with the right case in their namespace.
///
/// # Example
/// ```mbt check
/// test {
///   guard @vdom.h("div", attrs={ "id": Str("app") }, childs=[@vdom.text("hi")])
///     is Node(el)
///   inspect(el.tag, content="DIV")
///   assert_true(el.attrs.get("id") is Some(Str("app")))
/// }
/// ```
pub fn h(
  tag : String,
  attrs? : Map[String, AttrValue] = Map([]),
  childs? : Array[Vdom] = [],
  key? : String,
  ns? : Ns,
) -> Vdom {
  let mut key = key
  let mut ns = ns
  // `attrs` is adopted, not copied, when there is nothing to strip out of it.
  // Two lookups against a copy of every entry — and, more to the point, the
  // caller can then hand the SAME map to every render of a static-attribute
  // element, which is what lets `diff_props`'s `physical_equal` fast path
  // answer in O(1) instead of hashing every key in both directions.
  //
  // A `@filter.VdomFilter` DOES mutate a VElem's attrs after construction (it
  // has to: rebuilding a node would defeat the identity fast path above). That
  // is safe only because every construction site inside this repo builds a
  // fresh map per render — `eval_attrs` and `clean_vdom` both do. A caller that
  // hands the same map to two renders and installs a filter would see the first
  // render's removals in the second.
  let props : Map[String, AttrValue] = if attrs.contains("key") ||
    attrs.contains("namespace") {
    let stripped : Map[String, AttrValue] = Map([])
    for name, value in attrs {
      match name {
        "key" => if key is None { key = Some(value.to_attr_string()) }
        "namespace" =>
          if ns is None && value is Str(uri) {
            ns = Some(Ns::from_uri(uri))
          }
        _ => stripped[name] = value
      }
    }
    stripped
  } else {
    attrs
  }
  let mut tag = tag
  if ns is None {
    match tag.to_lower() {
      "svg" => {
        ns = Some(Svg)
        tag = "svg"
      }
      "math" => {
        ns = Some(MathMl)
        tag = "math"
      }
      _ => ()
    }
  }
  let tag = if ns is None &&
    tag.get_char(0) is Some('a'..='z') &&
    tag == tag.to_lower() {
    tag.to_upper()
  } else {
    tag
  }
  Node({ tag, attrs: props, childs: normalize_childs(childs), key, ns })
}
