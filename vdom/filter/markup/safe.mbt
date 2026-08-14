// The two markup directives whose names carry no warning.

///|
/// Replaces `@setinnerhtml` and `@setinnersvg` with the sanitized nodes their
/// payloads parse to.
///
/// ## Why this is not `MarkupFilter` with the permission taken out
///
/// It is very nearly that, and the difference is worth being precise about,
/// because "we removed the safety check and renamed it safe" would be the wrong
/// change to make.
///
/// `@dangerouslysetinnerhtml` earns its name from what happens when nobody
/// filters it: `set_prop` hands the payload to `set_inner_html` and the browser
/// parses it, unexamined. `SanitizerConfig.raw_markup` is a permission because
/// that is the only lever a host has over the construct — installing
/// `MarkupFilter` makes it safe, but nothing in the type system says the host
/// did, so the default has to be no.
///
/// These two have no such fallback. `set_prop` fails CLOSED on both names
/// (`vdom/to_dom.mbt`), the same way it does on `@setinnermd`: an app mounted
/// with no filter renders an empty element rather than unchecked markup. So the
/// question a permission would answer — "might this reach the DOM unexamined?"
/// — has one answer already, and it is no. There is nothing left to grant, Pass
/// 1 never refuses them (`anode/sanitize/sanitize.mbt`), and this filter reads
/// no permission field.
///
/// The other half of the argument is that the capability is not new.
/// `@setinnermd` already routes a markdown document's `HtmlBlock` and
/// `HtmlInline` through `html_nodes` with no permission at all
/// (`vdom/filter/markdown/build.mbt`), and `MdFilter` is installed by
/// `App::new`. Arbitrary runtime HTML becoming sanitized nodes is what a
/// default app has always done; these directives give it a name instead of
/// making an author wrap it in a markdown payload to reach it.
///
/// ## Nodes, not a string
///
/// Same as `MarkupFilter` and for the same reason, set out at length in
/// `markup.mbt`: parse once, sanitize the tree, hand back `@vdom.Vdom`. A
/// sanitized string that the browser parses a second time is the mutation-XSS
/// vector, and there is no second parse here.
///
/// ## One filter for two directives
///
/// Two names, one struct, one `filter_elem`. `Chain` is for filters that need
/// separate passes — one that REPLACES a subtree has to finish before one that
/// inspects attributes — and these two do not: they are mutually exclusive on a
/// given element and both replace. Two members would cost a second call per
/// element per render for nothing, which is the same argument `Baseline` makes
/// about the URL and handler rules.
pub struct SafeMarkupFilter {
  /// The host's sanitizer, narrowed to what a payload may carry. See
  /// `CssPolicy::payload` for what that is, and `without_css` for why the
  /// narrowing is an overlay rather than a config.
  sanitizer : @sanitize.Sanitizer
  log : @filter.DropLog
}

///|
/// The attribute name `eval_attrs` writes an `@setinnerhtml` payload under
/// (`render/render.mbt`), which is also one of the names `set_prop` fails
/// closed on.
pub const SAFE_HTML_ATTR : String = "setInnerHtml"

///|
/// The `@setinnersvg` half of the pair.
pub const SAFE_SVG_ATTR : String = "setInnerSvg"

///|
/// The sanitizer handed in is narrowed on the way in, so a caller cannot
/// construct this filter with an app's own CSS policy by forgetting to.
///
/// It used to be narrowed by `without_css`, which dropped `style` entirely
/// because there was no parser to tell a colour from a `url()`. There is one
/// now, so the narrowing is `CssPolicy::payload()`: a payload may lay itself
/// out and paint itself, may point at an SVG gradient it defined, and may not
/// fetch, overlay, or carry a `<style>` block.
pub fn SafeMarkupFilter::new(
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
  max_reports? : Int = 64,
) -> SafeMarkupFilter {
  {
    sanitizer: sanitizer.with_css(@safecss.CssPolicy::payload()),
    log: @filter.DropLog::new(max_reports~),
  }
}

///|
/// Everything dropped since the last call, and clears the log.
pub impl @filter.VdomFilter for SafeMarkupFilter with fn take_reports(self) {
  self.log.take()
}

///|
fn SafeMarkupFilter::record(
  self : SafeMarkupFilter,
  tag : String,
  attr : String,
  value : String,
  reason : String,
) -> Unit {
  self.log.record({ tag, attr, value, reason })
}

///|
/// Nothing to replace when the element carries no markup payload, which
/// `render` decided off the view tree — see `@sinks.SinkHints`. A payload
/// arrives under one of four fixed directive names, so this is a name question
/// like the others.
pub impl @filter.VdomFilter for SafeMarkupFilter with fn filter_elem_hinted(
  self,
  el,
  hints,
) {
  if hints.markup {
    self.filter_elem(el)
  }
}

///|
/// The rule for one element; the caller decides when to call it.
///
/// Like the other two replacing filters, this runs where `render` CONSTRUCTS an
/// element, so nothing runs after it on the subtree it creates — everything it
/// builds is checked by `html_nodes` / `svg_nodes` or by nothing.
pub impl @filter.VdomFilter for SafeMarkupFilter with fn filter_elem(self, el) {
  self.replace(el, SAFE_HTML_ATTR)
  self.replace(el, SAFE_SVG_ATTR)
}

///|
/// One directive's worth of the rule.
///
/// Both names on one element is not a case worth designing for — an author who
/// writes both gets the SVG one, because it runs second and each clears the
/// children the other set. Refusing the combination would need a report channel
/// aimed at an author, and by render time there is no author to aim it at.
fn SafeMarkupFilter::replace(
  self : SafeMarkupFilter,
  el : @vdom.VElem,
  attr : String,
) -> Unit {
  let payload = match el.attrs.get(attr) {
    Some(SafeHtml(s)) if attr == SAFE_HTML_ATTR => s
    Some(Svg(s)) if attr == SAFE_SVG_ATTR => s
    // A value of the wrong shape under that name is not something to reason
    // about — drop the attribute so `set_prop`'s fail-closed branch does not
    // clear an element over it, exactly as `MdFilter` does.
    Some(_) => {
      el.attrs.remove(attr)
      return
    }
    None => return
  }
  el.attrs.remove(attr)
  let on_drop = (t, a, v, r) => self.record(t, a, v, r)
  let built = if attr == SAFE_SVG_ATTR {
    svg_nodes(self.sanitizer, payload, el.tag, on_drop, attr~)
  } else {
    html_nodes(self.sanitizer, payload, el.tag, on_drop, attr~)
  }
  // The directive replaces the element's content, the way the other two do;
  // children the element also declared were never going to survive.
  el.childs.clear()
  for node in built {
    el.childs.push(node)
  }
}
