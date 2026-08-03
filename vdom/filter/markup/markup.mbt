// Turning a raw-markup payload into described nodes.

///|
/// Replaces `@dangerouslysetinnerhtml` with the sanitized nodes its payload
/// parses to.
///
/// ## Why nodes and not a string
///
/// The obvious port of `setHTML()` is: parse the payload, prune it, serialize
/// it back, hand the result to `set_inner_html`. That is the shape this design
/// document originally described, and it is wrong for a reason that has bitten
/// every sanitizer that shipped it — the browser then parses the string a
/// SECOND time, and any disagreement between the two parsers is a mutation-XSS
/// vector. Markup that looks inert to the sanitizer's parser can come back to
/// life in the browser's.
///
/// Building vdom nodes removes the second parse entirely. The payload is
/// parsed once, sanitized as a tree, and rendered through exactly the machinery
/// every other node goes through — `to_dom`'s `create_element` and `set_prop`,
/// with `set_inner_html` never called at all. That is also what the platform's
/// own API does: `Sanitizer` operates on nodes, and `setHTML` parses once.
///
/// ## What this changes
///
/// With this filter installed, `@dangerouslysetinnerhtml` sets CHILDREN rather
/// than `innerHTML`. Anything the payload names that the config refuses is
/// gone, and what remains diffs like ordinary children rather than being
/// re-parsed on every render. Without it installed, the directive behaves as it
/// always has — so this is opt-in, and installing it is what makes the
/// construct safe rather than merely dangerous.
pub struct MarkupFilter {
  sanitizer : @sanitize.Sanitizer
  reports : Array[@filter.Dropped]
  max_reports : Int
}

///|
/// The attribute name `eval_attrs` writes a raw-markup payload under
/// (`render/render.mbt`), which is also the name `set_prop` looks for.
pub const RAW_ATTR : String = "dangerouslySetInnerHTML"

///|
pub fn MarkupFilter::new(
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
  max_reports? : Int = 64,
) -> MarkupFilter {
  { sanitizer, reports: [], max_reports }
}

///|
/// Everything dropped since the last call, and clears the log.
pub impl @filter.VdomFilter for MarkupFilter with fn take_reports(self) {
  let out = self.reports.copy()
  self.reports.clear()
  out
}

///|
fn MarkupFilter::record(
  self : MarkupFilter,
  tag : String,
  attr : String,
  value : String,
  reason : String,
) -> Unit {
  if self.reports.length() < self.max_reports {
    self.reports.push({ tag, attr, value, reason })
  }
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
/// The rule for one element; the caller decides when to call it.
///
/// The nodes this builds are sanitized by `build_payload` itself, attribute
/// VALUES included, and that is load-bearing rather than belt-and-braces:
/// `render` calls this as it CONSTRUCTS each element, so nothing runs after it
/// on a subtree it created. (Under `filter_tree`'s `walk_elems`, the walk does
/// descend into them afterwards — but a filter cannot assume the caller walks
/// at all, and the one that matters does not.)
pub impl @filter.VdomFilter for MarkupFilter with fn filter_elem(self, el) {
  match el.attrs.get(RAW_ATTR) {
    Some(Html(payload)) => {
      el.attrs.remove(RAW_ATTR)
      let built = self.build_payload(el.tag, payload)
      // `set_inner_html` replaces everything, so children the element also
      // declared were never going to survive; clearing keeps that.
      el.childs.clear()
      for node in built {
        el.childs.push(node)
      }
    }
    // A non-`Html` value under that name is what `set_prop` treats as the
    // empty payload; drop the attribute rather than reasoning about it.
    Some(_) => el.attrs.remove(RAW_ATTR)
    None => ()
  }
}

///|
/// Parse a payload and sanitize it into nodes.
///
/// Parsed through `@anode.parse_fragment`, so the payload sees the same
/// template-content insertion mode a view does — a bare `<tr>` or `<option>`
/// survives instead of being dropped or foster-parented.
fn MarkupFilter::build_payload(
  self : MarkupFilter,
  host_tag : String,
  payload : String,
) -> Array[@vdom.Vdom] {
  let (doc, roots) = @anode.parse_fragment(payload)
  let out : Array[@vdom.Vdom] = []
  for id in roots {
    match self.build_node(doc, id, host_tag) {
      Some(node) => out.push(node)
      None => ()
    }
  }
  out
}

///|
fn MarkupFilter::build_node(
  self : MarkupFilter,
  doc : @html5.Document,
  id : Int,
  host_tag : String,
) -> @vdom.Vdom? {
  match doc.get_node(id) {
    Some(TextNode(s)) => Some(Text(s))
    Some(CommentNode(s)) =>
      if self.sanitizer.comments {
        Some(Comment(s))
      } else {
        None
      }
    Some(ElementNode(el)) => self.build_element(doc, id, el, host_tag)
    // Doctypes and the like cannot appear in template content; drop rather
    // than reason about them.
    _ => None
  }
}

///|
fn MarkupFilter::build_element(
  self : MarkupFilter,
  doc : @html5.Document,
  id : Int,
  el : @html5.Element,
  host_tag : String,
) -> @vdom.Vdom? {
  let tag = el.tag_name
  let sns = sanitize_ns(el.ns)
  fn children() -> Array[@vdom.Vdom] {
    let kids : Array[@vdom.Vdom] = []
    for child_id in doc.get_children(id) {
      match self.build_node(doc, child_id, host_tag) {
        Some(node) => kids.push(node)
        None => ()
      }
    }
    kids
  }

  match self.sanitizer.element_verdict(tag, sns) {
    Drop => {
      self.record(host_tag, RAW_ATTR, "<\{tag}>", "element is not allowed here")
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
          self.record(
            host_tag,
            name,
            value,
            "attribute is not allowed on <\{tag}> here",
          )
          continue
        }
        // The value half, which the config has no opinion about. Nothing else
        // will look at this subtree, so it is checked here or nowhere.
        if !@filter.attr_value_allowed(name, value) {
          self.record(
            host_tag, name, value, "URL scheme is not one a view may navigate to",
          )
          continue
        }
        attrs[name] = Str(value)
      }
      Some(@vdom.h(tag, attrs~, childs=children(), ns?=vdom_ns(el.ns)))
    }
  }
}
