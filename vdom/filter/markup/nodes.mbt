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
  /// The directive the payload arrived under, for the report only. Four
  /// directives reach this builder now, so "dropped `dangerouslySetInnerHTML`"
  /// would be a lie in three of them — and a developer reading a drop log wants
  /// to know which attribute in their view to go and look at.
  attr : String
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
  attr? : String = RAW_ATTR,
) -> Array[@vdom.Vdom] {
  let (doc, roots) = @anode.parse_fragment(html)
  build_roots({ sanitizer, host_tag, attr, on_drop }, doc, roots)
}

///|
/// Parse an SVG payload and sanitize it into vdom nodes.
///
/// The SVG twin of `html_nodes`, and deliberately the same function with one
/// line changed: `@anode.parse_fragment_svg` instead of `@anode.parse_fragment`.
/// Everything after the parse — the walk, the verdicts, the attribute-value
/// rule — is shared, which is the same argument this file's header makes about
/// having one builder rather than two. A `<script>` cannot be refused in an
/// HTML payload and allowed in an SVG one, and `svg("script")` being a separate
/// baseline entry from `html("script")` is handled where it should be, in the
/// sanitizer's namespace-qualified keys, rather than by a second copy of this
/// walk.
///
/// What the different parse buys is the NAMESPACE. A bare `<circle/>` is an
/// unknown HTML element to `parse_fragment` and an SVG circle to this one, and
/// the sanitizer asks a different question of each. It also means the payload
/// cannot leave the namespace it was promised: the only route back to HTML is
/// `<foreignObject>`, which the parser labels as HTML and which is therefore
/// judged as HTML.
pub fn svg_nodes(
  sanitizer : @sanitize.Sanitizer,
  svg : String,
  host_tag : String,
  on_drop : (String, String, String, String) -> Unit,
  attr? : String = SAFE_SVG_ATTR,
) -> Array[@vdom.Vdom] {
  let (doc, roots) = @anode.parse_fragment_svg(svg)
  build_roots({ sanitizer, host_tag, attr, on_drop }, doc, roots)
}

///|
fn build_roots(
  b : Build,
  doc : @html5.Document,
  roots : Array[Int],
) -> Array[@vdom.Vdom] {
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
/// A namespaced foreign attribute, back in the spelling everything downstream
/// uses.
///
/// The parser implements WHATWG 13.2.6.4 "adjust foreign attributes", which
/// splits a qualified name into prefix and local name and hands the pair back
/// SPACE-separated: `xlink:href` in source arrives here as `xlink href`. That
/// is faithful — the space stands for the namespace split a `setAttributeNS`
/// call would make — and it is wrong for us in two ways.
///
/// It is a hole. `@filter.url_attrs` knows `xlink:href`, and so does
/// `untrusted_sink_attr` in `dyncomp/policy`, because that is the only spelling
/// a VIEW can write. Neither knows `xlink href`, so
/// `<a xlink:href="javascript:…">` inside a payload walked straight past the
/// URL rule. That predates the safe directives — it is reachable through
/// `@dangerouslysetinnerhtml` and through markdown's HTML blocks — but it is
/// this builder's to fix, because this is where the two spellings meet.
///
/// And it is broken output regardless. `vdom` has no namespaced-attribute path;
/// `set_prop` would reach `set_attribute("xlink href", …)`, and a space is not
/// a legal attribute name character, so a browser throws `InvalidCharacterError`
/// rather than setting anything.
///
/// Folding back to the colon form fixes both: every existing rule matches, and
/// `setAttribute("xlink:href", …)` is a legal call that SVG resolves the way an
/// author meant. It is not `setAttributeNS`, and for these seven names the
/// difference does not reach the page.
fn foreign_attr_name(name : String) -> String {
  match name {
    "xlink actuate"
    | "xlink arcrole"
    | "xlink href"
    | "xlink role"
    | "xlink show"
    | "xlink title"
    | "xlink type"
    | "xml lang"
    | "xml space"
    | "xmlns xlink" => name.replace(old=" ", new=":")
    _ => name
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
        self.attr,
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
        let (raw_name, value) = pair
        // Folded before ANY rule reads it, so no rule has to know about the
        // parser's space form. See `foreign_attr_name`.
        let name = foreign_attr_name(raw_name)
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
