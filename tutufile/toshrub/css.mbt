// A raw-text style block, converted to shrubbery-css notation.
//
// `marianoguerra/shrubbery-css` already goes CSS -> notation (`to_shrubbery`),
// so this is a wrapper around it plus the one thing it cannot know: a tutuca
// scoped style is a rule BODY, not a stylesheet, and its top level may hold
// bare declarations. Those are wrapped in a synthetic rule before the
// conversion and unwrapped after -- the same trick the reader plays in the
// other direction.

///|
/// The notation for a raw CSS block, indented, or `None` if it will not convert.
///
/// `None` rather than a raise: a block that does not convert stays raw text,
/// which is a spelling the notation keeps on purpose. Nothing is lost by
/// leaving one behind.
pub fn css_block(
  css : String,
  indent : String,
  global : Bool,
) -> String? {
  let src = if global { css } else { "scope{" + css + "}" }
  let shrub = @shrubcss.to_shrubbery(src) catch { _ => return None }
  let lines = []
  for line in shrub.split("\n") {
    lines.push(line.to_owned())
  }
  // Unwrap the synthetic rule: drop its header and one level of indentation.
  let body = if global {
    lines
  } else {
    let out = []
    let mut first = true
    for line in lines {
      if first {
        first = false
        continue
      }
      if line.trim(chars=" ") == "" {
        continue
      }
      out.push(if line.has_prefix("  ") { line[2:].to_owned() } else { line })
    }
    out
  }
  let text = StringBuilder()
  for line in body {
    if line.trim(chars=" ") == "" {
      continue
    }
    text.write_string(indent + line + "\n")
  }
  let out = text.to_string()
  if out == "" {
    return None
  }
  Some(out)
}

///|
/// Whether two spellings of one style block mean the same CSS.
///
/// The two sides are different LANGUAGES -- one is CSS and one is notation --
/// so each is taken to a stylesheet by its own reader and both are printed by
/// the same printer at `Minified`. Comparing the two texts directly is the
/// mistake this replaced: it parsed the notation as CSS, which fails for every
/// input and reports every conversion as a difference.
pub fn css_agrees(raw : String, notation : String, global : Bool) -> Bool {
  let want = of_css(if global { raw } else { "scope{" + raw + "}" })
  let src = if global {
    notation
  } else {
    let b = StringBuilder()
    b.write_string("scope:\n")
    for line in notation.split("\n") {
      if line.trim(chars=" ") != "" {
        b.write_string("  " + line.to_owned() + "\n")
      }
    }
    b.to_string()
  }
  let got = of_notation(src)
  want is Some(a) && got is Some(b) && a == b
}

///|
/// A CSS source, as minified CSS.
fn of_css(css : String) -> String? {
  let p = @cssparse.parse(css) catch { _ => return None }
  if p.has_errors() {
    return None
  }
  Some(@csswrite.stylesheet(p.sheet(), style=Minified))
}

///|
/// A notation source, as minified CSS.
fn of_notation(src : String) -> String? {
  let out = @shrubcss.lower(src) catch { _ => return None }
  if out.has_errors() {
    return None
  }
  Some(@csswrite.stylesheet(out.sheet(), style=Minified))
}

///|
/// A style block's CSS, normalised, for comparing two spellings of it.
///
/// Byte comparison is the wrong question for a CSS conversion: `.mine { color:
/// red; }` and `.mine{color:red}` are one stylesheet, and a check that called
/// them different would refuse every conversion it was written to allow. What
/// has to hold is that the STYLESHEET is the same, so both sides go through the
/// same parser and the same printer.
///
/// Unparseable input comes back unchanged, so a block this cannot read is still
/// compared -- as text, which is the strictest thing left to do with it.
pub fn css_key(raw : String) -> String {
  match of_css("scope{" + raw + "}") {
    Some(css) => css
    None => raw
  }
}
