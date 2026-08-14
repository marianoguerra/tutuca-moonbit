// The CSS value rule, for a tree that is not a payload.
//
// ## What this is for, and what already covers the rest
//
// The three payload filters — `@markup.MarkupFilter`, `@markup.SafeMarkupFilter`
// and `@markdown.MdFilter` — each validate the CSS in what they BUILD, because
// nothing runs after a filter on nodes it created. That is the half of the
// problem that matters most, and it is closed without this type.
//
// What is left is an app's OWN tree: a `:style="…"` whose value comes out of
// application state, which routinely includes something a person typed. Pass 1
// cannot decide it (the value is an expression, not a literal) and no payload
// filter ever sees it, so today nothing reads it at all.
//
// ## Why `Baseline` does not install it
//
// It would be a behaviour change that costs real pages, for a threat model the
// payload filters already cover better.
//
// Two things `CssPolicy::app()` refuses are ordinary in app-authored CSS. An
// unquoted `url(/logo.png)` is refused — css-syntax-3 gives the unquoted form
// its own token type that `mizchi/css/token` does not implement, so admitting
// it would mean reassembling a URL from `Delim` and `Ident` tokens and hoping
// the browser agrees, which is the mistake this package exists not to make. And
// `!important` is refused at every level, which is right for a value somebody
// else wrote and merely annoying for one the page's author wrote.
//
// So the default stays `Baseline`, which is the URL rule and the handler rule,
// and this is a thing a host adds when it knows its `style` values are not
// entirely its own:
//
// ```moonbit
// app.add_filter(@filter.CssFilter::new(@safecss.CssPolicy::payload()))
// ```
//
// One caveat with that spelling, and it is the reason this is not the whole
// story: `add_filter` appends BEHIND the built-in chain, and the URL rule must
// run after this one — this rewrites values and that one reads them. Behind
// `Baseline` it still validates and still drops, but a `url()` it rewrites is
// not re-read for its scheme afterwards. Composing it in FRONT is
// `@mdfilter.filter_for`'s business, which is where it will go when a policy
// asks for it.

///|
/// Validates `style` and the SVG presentation attributes against a policy, and
/// replaces each value with what the policy re-emitted.
///
/// It REWRITES rather than only dropping, which no other filter here does. That
/// is the whole mechanism: what reaches the DOM is generated from values the
/// validator understood, not the author's bytes with an approval stamp on them.
/// See `anode/sanitize/css`.
pub struct CssFilter {
  policy : @safecss.CssPolicy
  log : DropLog
}

///|
/// `policy` defaults to `payload()` — level `Computed`, no overlay, fragment
/// URLs only — because a host installing this at all is one that knows its
/// `style` values are not entirely its own.
pub fn CssFilter::new(
  policy? : @safecss.CssPolicy = @safecss.CssPolicy::payload(),
  max_reports? : Int = 64,
) -> CssFilter {
  { policy, log: DropLog::new(max_reports~) }
}

///|
pub impl VdomFilter for CssFilter with fn take_reports(self) {
  self.log.take()
}

///|
/// Whether this attribute carries a CSS value, without allocating to find out.
///
/// The same shape as `is_url_attr` and for the same reason: this runs on every
/// attribute of every element on every render, and almost none of them is one.
/// `style` is a declaration list; every other name here is an SVG presentation
/// attribute, which sets the CSS property of the same name with the same
/// grammar — which is why `fill="url(…)"` is a fetch and `fill="red"` is not.
pub fn is_css_attr(name : String) -> Bool {
  if name == "style" || @safecss.css_properties.contains(name) {
    return true
  }
  for c in name {
    if c is ('A'..='Z') {
      let lower = name.to_lower()
      return lower == "style" || @safecss.css_properties.contains(lower)
    }
  }
  false
}

///|
/// Nothing to look for when no attribute name carries a CSS value, which
/// `render` decided off the view tree — see `@sinks.SinkHints`. This is the
/// rule the hints save the most on: `is_css_attr` probes a set of 818 property
/// names, and `class`, `id` and `type` are in none of them.
pub impl VdomFilter for CssFilter with fn filter_elem_hinted(self, el, hints) {
  if hints.css {
    self.filter_elem(el)
  }
}

///|
/// The rule for one element; the caller owns the walk.
pub impl VdomFilter for CssFilter with fn filter_elem(self, el) {
  let mut doomed : Array[String]? = None
  let mut rewritten : Array[(String, String)]? = None
  for name, value in el.attrs {
    if !is_css_attr(name) {
      continue
    }
    // A markup payload is the markup filters' problem: they validate what they
    // build, because nothing runs after them on a subtree they created. None of
    // the four names those arrive under is a CSS attribute, so this is a rule
    // rather than a coincidence.
    if value is (Html(_) | Md(_) | SafeHtml(_) | Svg(_)) {
      continue
    }
    let raw = value.to_attr_string()
    let attr = name.to_lower()
    // A structured value is not a declaration list, for the reason the URL rule
    // gives about `Data`: `set_prop` sends it down the property path and the
    // IDL setter's ToString reassembles it into a string nothing checked.
    let verdict = if value is Data(_) {
      None
    } else if attr == "style" {
      self.policy.declarations(raw, screen=target => {
        url_value_allowed("src", target)
      }).css
    } else {
      self.policy.value(attr, raw, screen=target => {
        url_value_allowed("src", target)
      })
    }
    match verdict {
      None => {
        match doomed {
          Some(names) => names.push(name)
          None => doomed = Some([name])
        }
        self.log.record({
          tag: el.tag,
          attr: name,
          value: raw,
          reason: "CSS value is not one this policy admits",
        })
      }
      Some(text) =>
        // Rewritten even when it did not change, so the value that reaches the
        // DOM is always the one this code produced. A conditional would make
        // "unchanged" mean "the author's bytes went through", which is the
        // property the design does not want to have to reason about.
        match rewritten {
          Some(pairs) => pairs.push((name, text))
          None => rewritten = Some([(name, text)])
        }
    }
  }
  if doomed is Some(names) {
    for name in names {
      el.attrs.remove(name)
    }
  }
  if rewritten is Some(pairs) {
    for pair in pairs {
      el.attrs[pair.0] = Str(pair.1)
    }
  }
}
