// Parsed HTML, sanitized into vdom nodes.
//
// Split out of `markup.mbt` and made public because `MarkupFilter` is no longer
// the only caller: `vdom/filter/markdown` needs exactly this for the two places
// raw HTML survives inside a markdown document (`HtmlBlock` and the HTML
// comments that are the only thing `HtmlInline` ever holds). One builder rather
// than two is not tidiness — it is the reason a `<script>` cannot be allowed by
// one path and refused by the other.

///|
/// Everything the walk needs that does not change as it descends.
priv struct Build {
  sanitizer : @sanitize.Sanitizer
  /// The element the payload is being built INTO, for the report only. The
  /// nodes here have no author to complain to, so a report has to say which
  /// host element the markup arrived at.
  host_tag : String
  /// `(tag, attr, value, reason)` — the shape of `@filter.Dropped`.
  on_drop : (String, String, String, String) -> Unit
}

///|
/// Parse an HTML payload and sanitize it into vdom nodes.
///
/// Parsed through `@anode.parse_fragment`, so the payload sees the same
/// template-content insertion mode a view does — a bare `<tr>` or `<option>`
/// survives instead of being dropped or foster-parented.
///
/// The nodes this returns are sanitized by this function, attribute VALUES
/// included. That is load-bearing rather than belt-and-braces: `render` calls a
/// filter as it CONSTRUCTS each element, so nothing runs after the filter on a
/// subtree the filter created. Checked here or nowhere.
pub fn html_nodes(
  sanitizer : @sanitize.Sanitizer,
  html : String,
  host_tag : String,
  on_drop : (String, String, String, String) -> Unit,
) -> Array[@vdom.Vdom] {
  let b = Build::{ sanitizer, host_tag, on_drop }
  let (doc, roots) = @anode.parse_fragment(html)
  let out : Array[@vdom.Vdom] = []
  for id in roots {
    match b.node(doc, id) {
      Some(node) => out.push(node)
      None => ()
    }
  }
  out
}

///|
/// The parser's namespace, as the sanitizer's config spells it.
fn sanitize_ns(ns : @html5.Namespace) -> @anode.Ns? {
  match ns {
    SVG => Some(Svg)
    MathML => Some(MathML)
    _ => None
  }
}

///|
/// The parser's namespace, as a vnode spells it. Not the same enum as above —
/// `@anode.Ns` has two cases and `@vdom.Ns` has three — which is why the two
/// conversions are written out rather than shared.
fn vdom_ns(ns : @html5.Namespace) -> @vdom.Ns? {
  match ns {
    SVG => Some(Svg)
    MathML => Some(MathMl)
    _ => None
  }
}

///|
fn Build::node(self : Build, doc : @html5.Document, id : Int) -> @vdom.Vdom? {
  match doc.get_node(id) {
    Some(TextNode(s)) => Some(Text(s))
    Some(CommentNode(s)) =>
      if self.sanitizer.comments {
        Some(Comment(s))
      } else {
        None
      }
    Some(ElementNode(el)) => self.element(doc, id, el)
    // Doctypes and the like cannot appear in template content; drop rather
    // than reason about them.
    _ => None
  }
}

///|
fn Build::element(
  self : Build,
  doc : @html5.Document,
  id : Int,
  el : @html5.Element,
) -> @vdom.Vdom? {
  let tag = el.tag_name
  let sns = sanitize_ns(el.ns)
  fn children() -> Array[@vdom.Vdom] {
    let kids : Array[@vdom.Vdom] = []
    for child_id in doc.get_children(id) {
      match self.node(doc, child_id) {
        Some(node) => kids.push(node)
        None => ()
      }
    }
    kids
  }

  match self.sanitizer.element_verdict(tag, sns) {
    Drop => {
      (self.on_drop)(
        self.host_tag,
        RAW_ATTR,
        "<\{tag}>",
        "element is not allowed here",
      )
      None
    }
    // The spec's `replaceWithChildrenElements`: the element goes, its content
    // stays.
    ReplaceWithChildren => Some(@vdom.fragment(children()))
    Keep => {
      let attrs : Map[String, @vdom.AttrValue] = Map([])
      for pair in el.attributes {
        let (name, value) = pair
        if !self.sanitizer.attribute_allowed(tag, sns, name) {
          (self.on_drop)(
            self.host_tag,
            name,
            value,
            "attribute is not allowed on <\{tag}> here",
          )
          continue
        }
        // The value half, which the config has no opinion about. Nothing else
        // will look at this subtree, so it is checked here or nowhere.
        if !@filter.attr_value_allowed(name, value) {
          (self.on_drop)(
            self.host_tag,
            name,
            value,
            "URL scheme is not one a view may navigate to",
          )
          continue
        }
        attrs[name] = Str(value)
      }
      Some(@vdom.h(tag, attrs~, childs=children(), ns?=vdom_ns(el.ns)))
    }
  }
}
