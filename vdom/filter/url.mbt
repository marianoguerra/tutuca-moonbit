// The URL-scheme rule: the half of the problem the Sanitizer API declines to
// answer.
//
// The spec's unsafe baseline is about script-bearing ELEMENTS and event-handler
// ATTRIBUTES; its own default configuration allows `href` on `<a>`, and
// `<a href="javascript:…">` survives `setHTML()` untouched. The platform
// answers that half with CSP and Trusted Types, neither of which anode can
// port. This is tutuca's answer, and it necessarily runs here rather than at
// registration: an attribute's value in a view is a `Val` expression, so what
// it will hold is unknowable until it holds it.

///|
/// Attributes that load or navigate to a URL.
///
/// `data` is `<object data>`, not the `data-*` prefix — those are a different
/// thing and are not in here.
pub let url_attrs : @set.Set[String] = @set.Set::from_array([
  "href", "src", "srcset", "action", "formaction", "ping", "poster", "data", "background",
  "xlink:href",
])

///|
/// The subset that NAVIGATES rather than loads a subresource.
///
/// The distinction exists for `data:` alone: `<img src="data:image/png;base64,…">`
/// is ordinary and useful, while `<a href="data:text/html,…">` is a document
/// that runs in the page's own origin.
pub let navigational_attrs : @set.Set[String] = @set.Set::from_array([
  "href", "action", "formaction", "ping", "data", "xlink:href",
])

///|
/// Attributes whose value is a LIST of URLs rather than one.
///
/// `srcset` is comma-separated candidates, each `<url> [descriptor]`; `ping` is
/// whitespace-separated. Checking only the whole string would miss
/// `"a.png 1x, javascript:…  2x"`.
fn is_url_list(name : String) -> Bool {
  name is ("srcset" | "ping")
}

///|
/// Schemes that execute rather than locate.
fn is_script_scheme(scheme : String) -> Bool {
  scheme is ("javascript" | "vbscript")
}

///|
/// The scheme of a URL, lowercased, or `None` for a relative one.
///
/// Normalizes the way a browser does before comparing, because the attacks are
/// all in the normalization: tab, newline and carriage return are stripped from
/// ANYWHERE in a URL (`java&#9;script:` is the classic), and leading C0
/// characters and spaces are trimmed. A `:` only introduces a scheme if it
/// comes before any `/`, `?` or `#` — otherwise `foo/bar:baz` would read as
/// scheme `foo/bar`.
pub fn scheme_of(raw : String) -> String? {
  let buf = StringBuilder()
  let mut leading = true
  for c in raw {
    // Stripped anywhere, not just at the front.
    if c is ('\t' | '\n' | '\r') {
      continue
    }
    if leading && c <= ' ' {
      continue
    }
    leading = false
    buf.write_char(c)
  }
  let s = buf.to_string()
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    if c is ('/' | '?' | '#') {
      return None
    }
    if c == ':' {
      if i == 0 {
        return None
      }
      return Some(s[:i].to_owned().to_lower())
    }
    i = i + 1
  }
  None
}

///|
/// Whether this value may be used as this attribute's URL.
///
/// A relative URL — no scheme at all — is always fine, and is what almost every
/// real value is.
pub fn url_value_allowed(attr : String, value : String) -> Bool {
  match scheme_of(value) {
    None => true
    Some(scheme) => {
      if is_script_scheme(scheme) {
        return false
      }
      if scheme == "data" && navigational_attrs.contains(attr) {
        return false
      }
      true
    }
  }
}

///|
/// Whether this attribute may carry this value.
///
/// The whole rule in one call: names that are not URLs pass, list-valued
/// attributes are split first, and the scheme decides the rest. This is the
/// entry point for anything building attributes rather than walking existing
/// ones — a sanitized raw-markup payload, say, whose subtree no other filter
/// will ever see.
pub fn attr_value_allowed(name : String, value : String) -> Bool {
  let attr = name.to_lower()
  if !url_attrs.contains(attr) {
    return true
  }
  for candidate in url_candidates(attr, value) {
    if !url_value_allowed(attr, candidate) {
      return false
    }
  }
  true
}

///|
/// The individual URLs in an attribute's value.
fn url_candidates(attr : String, value : String) -> Array[String] {
  if !is_url_list(attr) {
    return [value]
  }
  let out : Array[String] = []
  // srcset separates candidates with `,` and a candidate's URL from its
  // descriptor with whitespace; ping separates URLs with whitespace and has no
  // commas, so splitting on both is right for each.
  for part in value.split(",") {
    for token in part.to_owned().split(" ") {
      let t = token.trim(chars="\t\n\r").to_owned()
      if t != "" {
        out.push(t)
      }
    }
  }
  out
}

///|
/// Drops attribute values whose URL scheme executes.
///
/// Not configurable and not tier-dependent, because there is nothing to
/// configure: tutuca has no element event handlers by design — which is exactly
/// what makes a view a description — so there is no legitimate `javascript:`
/// URL in one.
///
/// What it does NOT do is decide element or attribute NAMES. Those are literals
/// in the tree and are settled at registration by `@sanitize`, which is both
/// cheaper and able to tell the author. This is only the part that could not be
/// known then.
pub struct UrlFilter {
  /// What was removed this render, oldest first. Bounded, so a component
  /// rendering a bad URL in a loop cannot grow it without limit.
  log : DropLog
}

///|
pub fn UrlFilter::new(max_reports? : Int = 64) -> UrlFilter {
  { log: DropLog::new(max_reports~), }
}

///|
/// Everything dropped since the last call, and clears the log.
pub impl VdomFilter for UrlFilter with fn take_reports(self) {
  self.log.take()
}

///|
fn UrlFilter::record(self : UrlFilter, d : Dropped) -> Unit {
  self.log.record(d)
}

///|
/// Whether an attribute name is in the URL set, without allocating to find out.
///
/// `url_attrs.contains(name.to_lower())` is the obvious spelling and it
/// allocates a String for EVERY attribute of EVERY element on EVERY render,
/// before discovering that the name is not a URL attribute at all — which is
/// what almost every name is. The filter runs on every render, so the no-op
/// path is the path that matters.
///
/// Anode lowercases every attribute name it reads (`AttrParser::parse`), so a
/// name arriving here in mixed case came from a hand-built vnode or from vdom's
/// own IDL spellings (`className`, `htmlFor`, `tabIndex`) — none of which are in
/// the URL set. The scan for an uppercase letter costs no allocation, and the
/// `to_lower` happens only for a name that has one.
pub fn is_url_attr(name : String) -> Bool {
  if url_attrs.contains(name) {
    return true
  }
  for c in name {
    if c is ('A'..='Z') {
      return url_attrs.contains(name.to_lower())
    }
  }
  false
}

///|
/// Nothing to look for when no attribute name is a URL's, which `render`
/// decided off the view tree — see `@sinks.SinkHints`.
pub impl VdomFilter for UrlFilter with fn filter_elem_hinted(self, el, hints) {
  if hints.url {
    VdomFilter::filter_elem(self, el)
  }
}

///|
/// The rule for one element; the caller owns the walk.
pub impl VdomFilter for UrlFilter with fn filter_elem(self, el) {
  // Collected first — removing from the map while iterating it is not a thing
  // to rely on — but allocated only if there is something to collect, since
  // dropping anything is the rare case and this runs per element per render.
  let mut doomed : Array[String]? = None
  for name, value in el.attrs {
    if !is_url_attr(name) {
      continue
    }
    // A markup payload is the markup filters' problem, not this one's — they
    // check the URLs inside what they build, because nothing runs after them on
    // a subtree they created. Unreachable in practice, since none of the four
    // attribute names these arrive under is in `url_attrs`; kept so that stays
    // true by rule rather than by coincidence.
    if value is (Html(_) | Md(_) | SafeHtml(_) | Svg(_)) {
      continue
    }
    let raw = value.to_attr_string()
    // A structured value is not a URL string — which is a reason to DROP it,
    // not to allow it. The reasoning holds about the MoonBit value and fails
    // about the browser:
    // `set_prop` sends `Data` down the PROPERTY path, the glue does
    // `node.href = <array>`, and the IDL setter's ToString turns
    // `["javascript:alert(1)"]` into `javascript:alert(1)` — a live script URL
    // in the host's origin, from an untrusted bundle, with no host
    // cooperation. Multi-element lists join with `,`, which is a JS comma
    // expression, so they work too.
    //
    // There is no legitimate structured value for a URL attribute, so the rule
    // needs no scheme inspection: the shape alone settles it.
    let reason = if value is Data(_) {
      Some("a structured value cannot be a URL")
    } else if !attr_value_allowed(name, raw) {
      Some("URL scheme is not one a view may navigate to")
    } else {
      None
    }
    if reason is Some(reason) {
      match doomed {
        Some(names) => names.push(name)
        None => doomed = Some([name])
      }
      self.record({ tag: el.tag, attr: name, value: raw, reason, })
    }
  }
  if doomed is Some(names) {
    for name in names {
      el.attrs.remove(name)
    }
  }
}
