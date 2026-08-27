// The entry points: a declaration list, and one property's value.

///|
/// Validate a `style` attribute's value and re-emit it canonically.
///
/// One declaration failing drops that declaration and nothing else — the same
/// call the URL rule makes for an attribute, and for the same reason: a
/// component that loses its colour is a component an author can still read,
/// while one that loses its whole `style` because of a typo in the third
/// declaration is a mystery. A failure of the LIST — an escape, an at-rule, an
/// unbalanced paren — drops everything, because at that point nothing is known
/// about where one declaration ended and the next began.
///
/// The output is never a substring of the input. See the note at the top of
/// `values.mbt` for why that inverts the rule `docs/sanitizer.md` argues for
/// HTML, and why the inversion is right.
pub fn CssPolicy::declarations(
  self : CssPolicy,
  src : String,
  screen? : (String) -> Bool = _ => false,
) -> CssResult {
  let dropped : Array[CssDrop] = []
  let urls : Array[String] = []
  if self.level is Deny {
    return {
      css: None,
      dropped: [{ property: "", reason: UnknownProperty, }],
      screened_urls: [],
    }
  }
  let toks = match normalize(src) {
    Ok(toks) => toks
    Err(reason) =>
      return {
        css: None,
        dropped: [{ property: "", reason, }],
        screened_urls: [],
      }
  }
  let out = StringBuilder()
  let mut kept = 0
  for run in split_on_semicolons(toks) {
    if kept + dropped.length() >= max_declarations {
      dropped.push({ property: "", reason: TooLarge, })
      break
    }
    match declaration_text(run[:], self, urls, screen) {
      Ok(None) => ()
      Ok(Some(text)) => {
        if kept > 0 {
          out.write_char(';')
        }
        out.write_string(text)
        kept += 1
      }
      Err(drop) => dropped.push(drop)
    }
  }
  {
    css: if kept == 0 {
      None
    } else {
      Some(out.to_string())
    },
    dropped,
    screened_urls: urls,
  }
}

///|
/// Validate ONE property's value: a presentation attribute (`fill`, `stroke`,
/// `stop-color`), or anywhere else a value arrives without a property name
/// attached to it.
///
/// `None` means the value did not survive, which for an attribute means drop
/// the attribute. There is no partial answer: a presentation attribute is one
/// value, so there is nothing to keep half of.
pub fn CssPolicy::value(
  self : CssPolicy,
  property : String,
  src : String,
  screen? : (String) -> Bool = _ => false,
) -> String? {
  let name = ascii_lower(property)
  if property_verdict(name, self) is Err(_) {
    return None
  }
  let toks = match normalize(src) {
    Ok(toks) => toks
    Err(_) => return None
  }
  for tok in toks {
    if tok is Semicolon {
      return None
    }
  }
  match value_text(toks[:], name, self, [], screen) {
    Ok(text) => Some(text)
    Err(_) => None
  }
}

///|
/// The same, but reporting what it dropped and what a caller must still screen.
pub fn CssPolicy::value_checked(
  self : CssPolicy,
  property : String,
  src : String,
  screen? : (String) -> Bool = _ => false,
) -> CssResult {
  let name = ascii_lower(property)
  if property_verdict(name, self) is Err(reason) {
    return {
      css: None,
      dropped: [{ property: name, reason, }],
      screened_urls: [],
    }
  }
  let toks = match normalize(src) {
    Ok(toks) => toks
    Err(reason) =>
      return {
        css: None,
        dropped: [{ property: name, reason, }],
        screened_urls: [],
      }
  }
  let urls : Array[String] = []
  match value_text(toks[:], name, self, urls, screen) {
    Ok(text) => { css: Some(text), dropped: [], screened_urls: urls, }
    Err(reason) =>
      { css: None, dropped: [{ property: name, reason, }], screened_urls: [], }
  }
}

///|
/// Split a token run on top-level semicolons.
///
/// Top-level because `normalize` has already refused every bracket and brace
/// and balanced every paren, so the only nesting left is a function call and a
/// `;` cannot appear inside one. Splitting on the token rather than on the
/// character is the point: `content: ";"` is one declaration, and a splitter
/// working on the string would make it two.
fn split_on_semicolons(
  toks : Array[@token.Token],
) -> Array[Array[@token.Token]] {
  let out : Array[Array[@token.Token]] = []
  let mut run : Array[@token.Token] = []
  for tok in toks {
    if tok is Semicolon {
      out.push(run)
      run = []
    } else {
      run.push(tok)
    }
  }
  out.push(run)
  out
}

///|
/// One declaration: `property : value`.
///
/// `Ok(None)` is an empty run — the trailing `;` every author writes, and the
/// `;;` a careless one does. Neither is a drop worth reporting.
fn declaration_text(
  run : ArrayView[@token.Token],
  policy : CssPolicy,
  urls : Array[String],
  screen : (String) -> Bool,
) -> Result[String?, CssDrop] {
  let mut i = 0
  while i < run.length() && run[i] is Whitespace {
    i += 1
  }
  if i >= run.length() {
    return Ok(None)
  }
  let raw = match run[i] {
    Ident(name) => name
    _ => return Err({ property: "", reason: Malformed("no property name"), })
  }
  if !is_plain_ascii_name(raw) {
    return Err({ property: "", reason: Malformed("property name"), })
  }
  // A custom property's name is case-SENSITIVE — `--Foo` and `--foo` are two
  // properties — so only a real property name is folded.
  let custom = raw is [.. "--", ..]
  let property = if custom { raw } else { ascii_lower(raw) }
  i += 1
  while i < run.length() && run[i] is Whitespace {
    i += 1
  }
  if !(i < run.length() && run[i] is Colon) {
    return Err({ property, reason: Malformed("no colon"), })
  }
  i += 1
  let value = run[i:]
  // `!important` overrides whatever the page said about this element, which for
  // a value the page's author did not write is the wrong way round: the host's
  // own scoped rules are the thing a payload should not be able to beat. No
  // level admits it, and no switch turns it on — an author who needs a
  // declaration to win can say so in the host's stylesheet, which the host
  // wrote.
  for j = 0; j < value.length(); j = j + 1 {
    if value[j] is Delim('!') {
      return Err({ property, reason: Important, })
    }
  }
  if custom {
    // The definition site is the ONLY place a token enters a custom property,
    // and `var()` substitutes tokens rather than a value — so `--x: url(evil)`
    // followed by `background-image: var(--x)` is the whole attack, and this is
    // where it is closed. Validated with no property context, since there is no
    // grammar to hold it against, and refused entirely at `Constant`, which
    // admits no `var()` to read it back with.
    if policy.level is Constant {
      return Err({ property, reason: UnknownProperty, })
    }
    return match value_text(value, "", policy, urls, screen) {
      Ok(text) => Ok(Some(property + ":" + text))
      Err(reason) => Err({ property, reason, })
    }
  }
  match property_verdict(property, policy) {
    Err(reason) => Err({ property, reason, })
    Ok(_) =>
      match value_text(value, property, policy, urls, screen) {
        Ok(text) => Ok(Some(property + ":" + text))
        Err(reason) => Err({ property, reason, })
      }
  }
}
