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
  let props : Map[String, AttrValue] = Map([])
  let mut key = key
  let mut ns = ns
  for name, value in attrs {
    match name {
      "key" => if key is None { key = Some(value.to_attr_string()) }
      "namespace" =>
        if ns is None && value is Str(uri) {
          ns = Some(Ns::from_uri(uri))
        }
      _ => props[name] = value
    }
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
