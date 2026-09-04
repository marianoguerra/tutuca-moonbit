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
  log : @filter.DropLog
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
  { sanitizer, log: @filter.DropLog::new(max_reports~), }
}

///|
/// Everything dropped since the last call, and clears the log.
pub impl @filter.VdomFilter for MarkupFilter with fn take_reports(self) {
  self.log.take()
}

///|
fn MarkupFilter::record(
  self : MarkupFilter,
  tag : String,
  attr : String,
  value : String,
  reason : String,
) -> Unit {
  self.log.record({ tag, attr, value, reason, })
}

///|
/// Nothing to replace when the element carries no markup payload, which
/// `render` decided off the view tree — see `@sinks.SinkHints`. A payload
/// arrives under one of four fixed directive names, so this is a name question
/// like the others.
pub impl @filter.VdomFilter for MarkupFilter with fn filter_elem_hinted(
  self,
  el,
  hints,
) {
  if hints.markup {
    @filter.VdomFilter::filter_elem(self, el)
  }
}

///|
/// The rule for one element; the caller decides when to call it.
///
/// The nodes this builds are sanitized by `html_nodes` itself, attribute
/// VALUES included, and that is load-bearing rather than belt-and-braces:
/// `render` calls this as it CONSTRUCTS each element, so nothing runs after it
/// on a subtree it created. (Under `filter_tree`'s `walk_elems`, the walk does
/// descend into them afterwards — but a filter cannot assume the caller walks
/// at all, and the one that matters does not.)
pub impl @filter.VdomFilter for MarkupFilter with fn filter_elem(self, el) {
  match el.attrs.get(RAW_ATTR) {
    Some(Html(payload)) => {
      el.attrs.remove(RAW_ATTR)
      let built = html_nodes(self.sanitizer, payload, el.tag, (t, a, v, r) => {
        self.record(t, a, v, r)
      })
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
