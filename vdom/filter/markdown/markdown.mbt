// Turning a markdown payload into described nodes.

///|
/// Replaces `@setinnermd` with the sanitized nodes its markdown parses to.
///
/// ## Why this is not the dangerous directive with a parser bolted on
///
/// `@dangerouslysetinnerhtml` earns its name because its payload IS markup: the
/// only thing a host can decide about it is whether to permit the construct at
/// all, which is what `SanitizerConfig.raw_markup` decides. Markdown is not
/// markup. It is a source language, and the only thing that turns it into
/// elements is `build.mbt` in this package — which asks the sanitizer for a
/// verdict on every element it emits and runs every attribute value it
/// synthesizes past `@filter.attr_value_allowed`. There is no path from a
/// markdown string to an element that skips those two questions.
///
/// So there is nothing here for a host to grant, and Pass 1 has nothing to
/// refuse. A host that wants less than the default says so the ordinary way,
/// by naming elements in its `SanitizerConfig` — an allow-list without `img`
/// gets a document with no images, from markdown and from anywhere else.
///
/// ## Nodes, not a string
///
/// The obvious implementation is markdown -> HTML text -> `set_inner_html`, and
/// it is wrong for the reason `markup.mbt` sets out at length: the browser then
/// parses the string, and there is no second parser here to have agreed with
/// it. This builds vdom nodes, which reach the DOM through `create_element` and
/// `set_prop` like every other node. `set_inner_html` is never called — the
/// attribute `set_prop` looks for is gone by then, and if it were not, the
/// fail-closed branch in `to_dom.mbt` would clear the element rather than write
/// anything.
///
/// It is also why the vendored parser stops at the AST: upstream's HTML
/// renderer would only have produced a string for us to re-parse.
pub struct MdFilter {
  sanitizer : @sanitize.Sanitizer
  log : @filter.DropLog
}

///|
/// The attribute name `eval_attrs` writes a markdown payload under
/// (`render/render.mbt`), which is also the name `set_prop` fails closed on.
pub const MD_ATTR : String = "setInnerMd"

///|
pub fn MdFilter::new(
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
  max_reports? : Int = 64,
) -> MdFilter {
  { sanitizer, log: @filter.DropLog::new(max_reports~) }
}

///|
/// Everything dropped since the last call, and clears the log.
pub impl @filter.VdomFilter for MdFilter with fn take_reports(self) {
  self.log.take()
}

///|
fn MdFilter::record(
  self : MdFilter,
  tag : String,
  attr : String,
  value : String,
  reason : String,
) -> Unit {
  self.log.record({ tag, attr, value, reason })
}

///|
/// The rule for one element; the caller decides when to call it.
///
/// Like `MarkupFilter`, this runs where `render` CONSTRUCTS an element, so
/// nothing runs after it on the subtree it creates — everything it builds is
/// checked here or nowhere.
pub impl @filter.VdomFilter for MdFilter with fn filter_elem(self, el) {
  match el.attrs.get(MD_ATTR) {
    Some(Md(source)) => {
      el.attrs.remove(MD_ATTR)
      let built = build(source, self.sanitizer, el.tag, (t, a, v, r) => {
        self.record(t, a, v, r)
      })
      // The directive replaces the element's content, the same way the raw
      // markup one does; children the element also declared were never going
      // to survive.
      el.childs.clear()
      for node in built {
        el.childs.push(node)
      }
    }
    // A non-`Md` value under that name is not something to reason about — drop
    // the attribute so `set_prop`'s fail-closed branch does not clear an
    // element over it.
    Some(_) => el.attrs.remove(MD_ATTR)
    None => ()
  }
}
