// The value grammar: which component values a level admits, and how each one
// is written back out.
//
// ## The shape of the rule, and why it is this shape
//
// A declaration's value is checked TOKEN BY TOKEN against a closed vocabulary,
// and every token that survives is re-emitted from what it MEANS rather than
// from the bytes it came from. Nothing is ever passed through.
//
// That inverts the rule `docs/sanitizer.md` argues for HTML, where
// re-serializing a sanitized tree is the mistake that has broken every
// sanitizer which shipped it. The inversion is correct, and it is worth being
// explicit about why, because the HTML mantra reads as if it applied here.
//
// A sanitized HTML payload becomes NODES. The browser parses the source once,
// and writing the tree back out as text adds a SECOND parse that can disagree
// with the first — that is mutation XSS, and the fix is to never produce the
// text.
//
// A CSS value is never nodes. It reaches the browser as a STRING that the
// browser parses, through `setAttribute("style", …)` or through a stylesheet,
// whatever this code does. There is exactly one browser parse either way. So
// emitting our own canonical string does not add a parse — it removes the
// chance that ours and theirs disagreed, because what the browser reads is
// generated from values we understood rather than from bytes we approved.
//
// The practical consequence is the one that matters: a declaration list that
// survives contains no byte the validator did not choose. There is nothing for
// an unparsed tail, a stray `}` or a cleverly-spelled function name to ride in
// on, because nothing rides.
//
// ## What is NOT the job
//
// CSS correctness. `text-align: 5px` is admitted at level `Computed` and the
// browser drops it as invalid, which costs nothing and is the browser's job to
// decide. The validator owes exactly one thing: that nothing it admits can
// fetch, execute, or leave the box it was given. Trying to also be a CSS
// grammar checker would mean a much larger surface to be wrong about, in the
// direction where being wrong refuses ordinary styling.
//
// Level `Constant` is the exception, and deliberately so: there the point IS a
// small, exactly-specified subset, so idents are held against the generated
// per-property keyword table. See `properties.mbt`.

///|
/// The units a dimension may carry.
///
/// Closed for tidiness rather than for safety — a dimension with a unit the
/// browser does not know makes the declaration invalid and nothing else. The
/// list is the CSS Values 4 set plus the resolution and grid units.
pub let units : @set.Set[String] = @set.Set::from_array([
  // <length>: font-relative, root-relative, viewport-relative, absolute.
  "em", "rem", "ex", "rex", "cap", "rcap", "ch", "rch", "ic", "ric", "lh", "rlh",
  "vw", "vh", "vi", "vb", "vmin", "vmax", "svw", "svh", "svi", "svb", "svmin", "svmax",
  "lvw", "lvh", "lvi", "lvb", "lvmin", "lvmax", "dvw", "dvh", "dvi", "dvb", "dvmin",
  "dvmax", "cm", "mm", "q", "in", "pt", "pc", "px",
  // <angle>, <time>, <frequency>, <resolution>, <flex>.
   "deg", "grad", "rad", "turn", "s", "ms", "hz", "khz", "dpi", "dpcm", "dppx", "x",
  "fr",
])

///|
/// The CSS-wide keywords, which every property takes.
pub let css_wide_keywords : @set.Set[String] = @set.Set::from_array([
  "inherit", "initial", "unset", "revert", "revert-layer",
])

///|
/// The functions level `Computed` admits, with what each one is for.
///
/// An allow-list, and a small one. Every entry is a function whose arguments
/// are numbers, colours, keywords or other admitted functions — nothing in here
/// can name a resource, read the document, or reach outside the value it sits
/// in. The notable absences are deliberate:
///
/// - `attr()` reads a content attribute into a value, which is a route from
///   markup into CSS and has been an exfiltration primitive more than once;
/// - `url()`, `src()`, `image()`, `image-set()`, `cross-fade()` and `element()`
///   name a resource. `url()` is handled separately, by `UrlRule`; the rest
///   have no fragment-only form worth the surface and are simply refused;
/// - `path()` and `counter()` take a string or a document reference;
/// - `expression()` is IE's script-in-CSS. It is not a CSS function at all, so
///   it would be refused as unknown anyway — it is named here so that reading
///   this list answers the question.
///
/// `var()` is admitted but is not in this table: it has its own rule, because
/// what makes it safe is validating where a custom property is DEFINED. See
/// `custom_property_value`.
pub let allowed_functions : @set.Set[String] = @set.Set::from_array([
  // Colour.
  "rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch", "color", "color-mix",
  "light-dark", "contrast-color",
  // Maths.
   "calc", "min", "max", "clamp", "round", "mod", "rem", "abs", "sign",
  // Images that are not resources: a gradient paints from its own arguments.
   "linear-gradient", "radial-gradient", "conic-gradient", "repeating-linear-gradient",
  "repeating-radial-gradient", "repeating-conic-gradient",
  // Easing.
   "cubic-bezier", "steps", "linear",
  // Sizing.
   "fit-content", "minmax", "repeat",
  // Basic shapes, for `clip-path` — geometry from numbers, no `path()`.
   "inset", "circle", "ellipse", "polygon", "xywh", "rect",
  // Filters. `drop-shadow` takes lengths and a colour, not a resource.
   "blur", "brightness", "contrast", "drop-shadow", "grayscale", "hue-rotate", "invert",
  "opacity", "saturate", "sepia",
])

///|
/// The transform and perspective functions, which move content and so are
/// gated by `overlay` wherever they appear rather than only on `transform`.
pub let overlay_functions : @set.Set[String] = @set.Set::from_array([
  "translate", "translatex", "translatey", "translatez", "translate3d", "scale",
  "scalex", "scaley", "scalez", "scale3d", "rotate", "rotatex", "rotatey", "rotatez",
  "rotate3d", "skew", "skewx", "skewy", "matrix", "matrix3d", "perspective",
])

///|
/// The delimiters a value may contain.
///
/// `+ - * /` are the maths operators and the value separators (`rgb(0 0 0 / .5)`,
/// `grid-area: 1 / 2`, `border-radius: 4px / 8px`). Nothing else: a `!` is
/// `!important`, which is refused by name in `declarations.mbt`, and a `:` or a
/// `;` inside a value means the splitter got something it should not have.
fn is_value_delim(c : Char) -> Bool {
  c is ('+' | '-' | '*' | '/')
}

///|
/// One value's worth of tokens, checked and re-emitted.
///
/// `property` is the lowercased property name, used at level `Constant` to look
/// up the generated keyword table; it is `""` for a custom property, where
/// there is no grammar to look anything up in.
///
/// Returns the canonical text, or the reason it did not survive. `urls` is
/// appended to rather than returned, so a caller collecting across a whole
/// declaration list keeps source order.
fn value_text(
  toks : ArrayView[@token.Token],
  property : String,
  policy : CssPolicy,
  urls : Array[String],
  screen : (String) -> Bool,
) -> Result[String, CssReason] {
  let out = StringBuilder()
  let mut i = 0
  let n = toks.length()
  let mut wrote = false
  // A `url()` is three tokens with a shape, not a token, so the loop consumes
  // it whole rather than judging its pieces.
  while i < n {
    let tok = toks[i]
    match tok {
      Whitespace => {
        // One space, and never a leading or trailing one: the canonical form of
        // a run of whitespace is a single space between two things.
        if wrote && i + 1 < n {
          out.write_char(' ')
        }
        i += 1
        continue
      }
      Function(raw) => {
        let name = ascii_lower(raw)
        if !is_plain_ascii_name(name) {
          return Err(BadValue(raw))
        }
        if name == "url" {
          match url_text(toks, i, policy, urls, screen) {
            Ok((text, next)) => {
              out.write_string(text)
              i = next
              wrote = true
              continue
            }
            Err(e) => return Err(e)
          }
        }
        if policy.level is Constant {
          return Err(Function(name))
        }
        if name == "var" {
          if !(toks[i + 1] is Ident(_)) {
            return Err(BadValue("var() without a custom property"))
          }
        } else if overlay_functions.contains(name) {
          if !policy.overlay {
            return Err(Overlay)
          }
        } else if !allowed_functions.contains(name) {
          return Err(Function(name))
        }
        out.write_string(name)
        out.write_char('(')
        i += 1
        wrote = true
        continue
      }
      _ => ()
    }
    match component_text(tok, property, policy) {
      Ok(text) => {
        out.write_string(text)
        wrote = true
      }
      Err(e) => return Err(e)
    }
    i += 1
  }
  let text = out.to_string().trim(chars=" ").to_owned()
  if text == "" {
    return Err(BadValue("empty"))
  }
  Ok(text)
}

///|
/// One token that is not a function call and not whitespace.
fn component_text(
  tok : @token.Token,
  property : String,
  policy : CssPolicy,
) -> Result[String, CssReason] {
  match tok {
    Ident(raw) => {
      if !is_plain_ascii_name(raw) {
        return Err(BadValue(raw))
      }
      let name = ascii_lower(raw)
      // A custom property NAME is case-sensitive and is not a keyword, so it
      // is written back exactly as it came and is not looked up.
      if name is [.. "--", ..] {
        return Ok(raw)
      }
      if policy.level is Constant && !constant_keyword_ok(property, name) {
        return Err(BadValue(raw))
      }
      Ok(raw)
    }
    Hash(value, _) => {
      if !is_hex_color(value) {
        return Err(BadValue("#\{value}"))
      }
      Ok("#" + ascii_lower(value))
    }
    Number(d, kind) => number_text(d, kind is Integer)
    Percentage(d) =>
      match number_text(d, false) {
        Ok(t) => Ok(t + "%")
        Err(e) => Err(e)
      }
    Dimension(d, unit) => {
      let u = ascii_lower(unit)
      if !units.contains(u) {
        return Err(BadValue(unit))
      }
      match number_text(d, false) {
        Ok(t) => Ok(t + u)
        Err(e) => Err(e)
      }
    }
    Comma => Ok(",")
    RightParen => Ok(")")
    LeftParen => Ok("(")
    Delim(c) =>
      if is_value_delim(c) {
        Ok(c.to_string())
      } else {
        Err(BadValue(c.to_string()))
      }
    @token.String(s) => {
      // Only reachable at `Computed`: `Constant` admits no string. The content
      // cannot contain a quote or a backslash — a quote would have ended the
      // token and a backslash was refused before tokenizing — so quoting it is
      // enough to contain it, and a `;` or `}` inside stays inside.
      if policy.level is Constant {
        return Err(BadValue("a string"))
      }
      for c in s {
        if c == '"' || c == '\\' || c.to_int() < 0x20 {
          return Err(BadValue("a string"))
        }
      }
      Ok("\"" + s + "\"")
    }
    _ => Err(BadValue(tok.to_string()))
  }
}

///|
/// A number, written back so that it reads as the same number.
///
/// The bound is not arithmetic caution: an integer past `Int` range would come
/// back out of `to_int` as something else entirely, and a value that changed on
/// the way through is the one thing a canonical emitter may never produce.
fn number_text(d : Double, integer : Bool) -> Result[String, CssReason] {
  if d.is_nan() || d.is_inf() || d.abs() >= 2147483648.0 {
    return Err(BadValue("\{d}"))
  }
  if integer || d == d.to_int().to_double() {
    Ok(d.to_int().to_string())
  } else {
    Ok(d.to_string())
  }
}

///|
/// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa` and nothing else.
fn is_hex_color(s : String) -> Bool {
  let n = s.length()
  if !(n is (3 | 4 | 6 | 8)) {
    return false
  }
  for c in s {
    let hex = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    if !hex {
      return false
    }
  }
  true
}

///|
/// A `url()`, from the `Function("url")` at `at` through its closing paren.
///
/// Two shapes are admitted and no other:
///
/// - `url(#name)` — a `Hash` token, which is exactly what a fragment is;
/// - `url("target")` — a `String` token.
///
/// The UNQUOTED non-fragment form is refused, and that is the one decision here
/// that costs an author something. css-syntax-3 gives it its own token type
/// (`<url-token>`) with its own escaping and whitespace rules, and
/// `mizchi/css/token` does not implement it — an unquoted `url(/a/b.png)`
/// arrives as a run of `Delim`, `Ident` and `Solidus` tokens that this code
/// would have to reassemble, guessing at the rules the tokenizer did not apply.
/// Reassembling a URL from pieces and hoping the browser agrees is precisely the
/// mistake this package exists to not make. Quote it and it is a string both
/// parsers read the same way.
fn url_text(
  toks : ArrayView[@token.Token],
  at : Int,
  policy : CssPolicy,
  urls : Array[String],
  screen : (String) -> Bool,
) -> Result[(String, Int), CssReason] {
  if at + 2 >= toks.length() {
    return Err(Malformed("unclosed url("))
  }
  let inner = toks[at + 1]
  if !(toks[at + 2] is RightParen) {
    return Err(Malformed("url() with more than one argument"))
  }
  let target = match inner {
    Hash(name, _) => "#" + name
    @token.String(s) => s
    _ =>
      return Err(Malformed("url() that is not a fragment or a quoted string"))
  }
  for c in target {
    if c == '"' || c == '\\' || c.to_int() < 0x20 {
      return Err(BadValue("url()"))
    }
  }
  match policy.url {
    NoUrl => Err(Url(target))
    FragmentOnly =>
      if target is ['#', ..] {
        Ok(("url(\"" + target + "\")", at + 3))
      } else {
        Err(Url(target))
      }
    Screened => {
      // A fragment is settled here. Anything else is the CALLER's to judge, and
      // it judges it now rather than afterwards: `screen` is the scheme rule
      // this package deliberately does not own, and its default REFUSES, so a
      // caller that asked for `Screened` and passed nothing gets `NoUrl` rather
      // than an unchecked URL. `screened_urls` then records what was admitted,
      // for a report, and not what still needs checking.
      if target is ['#', ..] {
        return Ok(("url(\"" + target + "\")", at + 3))
      }
      if !screen(target) {
        return Err(Url(target))
      }
      urls.push(target)
      Ok(("url(\"" + target + "\")", at + 3))
    }
  }
}
