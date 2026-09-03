///| Where an untrusted view may point a URL, once a host has said it may point
/// one anywhere at all.
///
/// The URL question splits in two, and the split is not the one it looks like.
/// A SCHEME is a render-time question — `javascript:` in an `href` is a value,
/// and `@filter.UrlFilter` is where a value is concrete. An ORIGIN does not
/// have to be: a view that writes its origin as a literal has settled it
/// before anything runs, and a view that computes its origin has settled
/// nothing. That is the whole of the rule here — the origin is a literal in
/// the view, so allowing external URLs allows the origins the HOST can read
/// in the bundle it is looking at, not the origins the guest picks later.
///
/// What it does NOT do is make the request safe. An image is a GET the guest
/// chose, and the path is still the guest's to fill in, so an allowed origin
/// is an origin that can be told things. Naming the origins is what turns
/// "this bundle can talk to anyone" into "this bundle can talk to the CDN its
/// pictures are on" — see SECURITY.md §3.

///|
/// An origin list that does not describe origins.
///
/// Loud rather than lenient, for the reason `@sanitize.InvalidConfig` is: the
/// list comes from the HOST, the one party here who can read a message and fix
/// it, and an entry that silently matched nothing would read as a policy that
/// was applied and turn out to be a policy that refused everything.
pub suberror InvalidOrigin {
  InvalidOrigin(Array[String])
}

///|
pub fn InvalidOrigin::to_string(self : InvalidOrigin) -> String {
  let InvalidOrigin(bad) = self
  "not http(s) origins: \{bad.join(", ")}"
}

///|
/// The same policy, allowing external URLs pinned to these origins.
///
/// One call rather than two fields a host sets separately, because they are
/// one decision: a list with no allowance permits nothing, and an allowance
/// with no list permits every `https://` origin there is. Both of those are
/// policies somebody would write by accident.
///
/// An entry is an origin — `https://cdn.bsky.app`, with or without a trailing
/// slash. A PATH in an entry is dropped rather than honored, and that is not a
/// shortcut: `https://cdn.example/public/../private/key` is a URL to
/// `/private/key`, so a path prefix is not a boundary and one that looked like
/// a boundary would be worse than none.
///
/// An empty list means any `https://` origin. It is the widest form this
/// allowance has and the one to justify before using: it still denies the
/// guest a computed origin, and denies it nothing else.
pub fn Policy::allowing_external_urls(
  self : Policy,
  origins : Array[String],
) -> Policy raise InvalidOrigin {
  let normalized : Array[String] = []
  let bad : Array[String] = []
  for entry in origins {
    match origin_of(with_authority_end(entry)) {
      Some(origin) =>
        if !normalized.contains(origin) {
          normalized.push(origin)
        }
      None => bad.push(entry)
    }
  }
  if !bad.is_empty() {
    raise InvalidOrigin(bad)
  }
  { ..self, allows_external_urls: true, external_origins: normalized, }
}

///|
/// An origin as this package writes them, or None for text that does not name
/// one: scheme lowercased, authority lowercased, and the `/` that ends the
/// authority on the end.
///
/// The public form of `origin_of` + `with_authority_end`, for the one caller
/// outside this package that has to produce the SAME string rather than judge
/// one — `host/bundle_config.mbt`, resolving a manifest's own origin defaults.
/// Exported as one function rather than two because the pair only ever makes
/// sense together, and a caller that ran them in the other order would get a
/// prefix test back instead of an origin.
pub fn normalized_origin(text : String) -> String? {
  match origin_of(with_authority_end(text)) {
    Some(o) => Some(o + "/")
    None => None
  }
}

///|
/// The index of the `:` in `://`, which is where a scheme ends.
fn scheme_end(url : String) -> Int? {
  let n = url.length()
  let mut i = 0
  while i + 2 < n {
    if url.get_char(i) is Some(':') &&
      url.get_char(i + 1) is Some('/') &&
      url.get_char(i + 2) is Some('/') {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// A host's entry with the `/` that ends an authority, so that an origin
/// written the way a person writes one parses like a URL.
fn with_authority_end(entry : String) -> String {
  guard scheme_end(entry) is Some(i) else { return entry }
  let mut j = i + 3
  while j < entry.length() {
    if entry.get_char(j) is Some('/') {
      return entry
    }
    j = j + 1
  }
  entry + "/"
}

///|
/// The origin a URL states OUTRIGHT: scheme and authority, both complete, with
/// the `/` that ends the authority present in the text handed in.
///
/// `None` for anything less, and the "less" cases are the interesting ones:
///
/// - The text stops inside the authority (`https://cdn.example`), so whatever
///   follows in the real URL — an interpolation, a macro body's concatenation
///   — is still choosing the host.
/// - The authority carries USERINFO. `https://cdn.example@attacker.test/` has
///   origin `attacker.test` and reads as `cdn.example` to anything comparing
///   prefixes, which is the whole of the attack.
/// - A backslash, a control character or a space is in the authority: the
///   browser's own normalization strips or re-reads those, and an origin that
///   two parsers disagree about is not one to make a decision with.
fn origin_of(url : String) -> String? {
  guard scheme_end(url) is Some(i) else { return None }
  let scheme = url[:i].to_owned().to_lower()
  guard scheme is ("http" | "https") else { return None }
  let start = i + 3
  let mut j = start
  while j < url.length() && !(url.get_char(j) is Some('/')) {
    j = j + 1
  }
  guard j < url.length() else { return None }
  let authority = url[start:j].to_owned()
  guard authority != "" else { return None }
  for c in authority {
    if c is ('@' | '\\' | '?' | '#') || c <= ' ' {
      return None
    }
  }
  Some("\{scheme}://\{authority.to_lower()}")
}

///|
/// The literal head of a value: what is settled before anything the guest
/// evaluates can add to it.
///
/// A template's leading RUN of literal parts, stopping at the first one that is
/// not — because everything from there on is path, and an origin cannot be
/// extended once the `/` that ends it is in the literal, which is what
/// `origin_of` insists on.
///
/// A run rather than `parts[0]` alone because a literal head can arrive in more
/// than one piece. `$'{$$mediaOrigin}/{.path}'` splits into the host's origin,
/// the `/`, and the field: three parts whose first two are both settled, and
/// reading only the first would refuse a spelling that pins perfectly well.
/// Concatenating stops being safe exactly where the parts stop being literal,
/// which is the same place the old rule stopped.
///
/// `from_macro` is excluded: a `^name` constant is the CALLER's string wearing
/// a literal's shape, and the caller is the guest. A `$$name` constant is the
/// HOST's string wearing a literal's shape, so it is not excluded — that is the
/// whole of what config vars buy (`config.mbt`).
fn pinned_prefix(val : @tutuca.Val) -> String? {
  match val {
    ELit(lit=LStr(s), from_macro=false, ..) => Some(s)
    ETpl(parts~, ..) => {
      let buf = StringBuilder()
      for part in parts {
        guard part is TText(text~, from_macro=false) else { break }
        buf.write_string(text)
      }
      let head = buf.to_string()
      if head == "" {
        None
      } else {
        Some(head)
      }
    }
    _ => None
  }
}

///|
/// Why this origin is not one to load from, or None when it is.
fn Policy::origin_refusal(self : Policy, origin : String) -> String? {
  if self.external_origins.is_empty() {
    return if origin is [.. "https://", ..] {
      None
    } else {
      Some(
        "'\{origin}' is not https, and this host allows any https origin and nothing else",
      )
    }
  }
  if self.external_origins.contains(origin) {
    return None
  }
  Some(
    "'\{origin}' is not an origin this host allows (\{self.external_origins.join(", ")})",
  )
}

///|
/// Why this value may not be a URL in an untrusted view, or None when it may.
///
/// The message is the whole point of returning a string rather than a Bool: a
/// refusal a guest author cannot act on produces a bundle that gets rewritten
/// at random until it loads.
fn Policy::external_url_refusal(self : Policy, val : @tutuca.Val) -> String? {
  if !self.allows_external_urls {
    return Some("this host does not allow external URLs in views")
  }
  guard pinned_prefix(val) is Some(prefix) else {
    return Some(
      "the value must BEGIN with a literal absolute URL, as in $'https://cdn.example/{.path}', so the origin is settled by the view rather than computed at render",
    )
  }
  guard origin_of(prefix) is Some(origin) else {
    return Some(
      "'\{prefix}' does not pin an origin: the literal has to run through the '/' that ends the authority, as in $'https://cdn.example/{.path}'",
    )
  }
  self.origin_refusal(origin)
}

///|
/// Whether this macro argument reads as a URL, and so is one the macro's body
/// could place in a sink.
///
/// Normalized the way a browser normalizes before it decides, because that is
/// where the disagreements live: tab, newline and carriage return are stripped
/// from ANYWHERE in a URL, and leading controls and spaces are trimmed.
fn url_shaped(raw : String) -> String? {
  let buf = StringBuilder()
  let mut leading = true
  for c in raw {
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
  guard s != "" else { return None }
  // Rooted: `/pixel` and `\\attacker.test` are both requests, and the second
  // is a protocol-relative URL in every browser that matters.
  if s is (['/', ..] | ['\\', ..]) {
    return Some(s)
  }
  // Schemed: a `:` only introduces a scheme when it comes before any `/`, `?`
  // or `#` — otherwise `alt/text:here` would read as one. Walked by CHARACTER
  // rather than by index, so a string carrying an astral character is text to
  // be read rather than a boundary to trip over.
  let mut first = true
  for c in s {
    if c is ('/' | '?' | '#') {
      return None
    }
    if c == ':' {
      return if first { None } else { Some(s) }
    }
    first = false
  }
  None
}

///|
/// The literal text a macro argument states, and nothing after the point where
/// something else can add to it.
///
/// `Attrs::to_macro_vars` hands every argument over as value SOURCE — a macro
/// substitutes `^name` textually and the body re-parses the result — so a
/// constant arrives quoted (`'/logout'`) and a template arrives as `$'…{…}…'`.
/// Reading the two shapes back is what lets one rule cover both, and what
/// keeps this from judging `'/logout'` by a leading quote it did not write.
///
/// Anything else is an expression — `.avatar`, `$url`, `equals? .a .b` — whose
/// text does not exist until it renders. Those are `None`, which is this
/// rule's honest limit rather than an oversight; SECURITY.md §3 says what that
/// leaves to the host that wrote the macro.
fn macro_arg_text(raw : String) -> String? {
  if raw is [.. "$'", .. rest] {
    // A template's head: everything up to the first placeholder.
    Some(literal_run(rest, stop_at_brace=true))
  } else if raw is ['\'', .. rest] {
    Some(literal_run(rest, stop_at_brace=false))
  } else {
    None
  }
}

///|
/// The text of a value-source string literal, up to its closing quote.
fn literal_run(rest : StringView, stop_at_brace~ : Bool) -> String {
  let buf = StringBuilder()
  let mut escaped = false
  for c in rest {
    if escaped {
      buf.write_char(c)
      escaped = false
      continue
    }
    if c == '\\' {
      escaped = true
      continue
    }
    if c == '\'' || (stop_at_brace && c == '{') {
      break
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Why this macro argument may not be handed to a macro by an untrusted view,
/// or None when it may.
///
/// A macro's BODY is the host's text and its arguments are the guest's, so an
/// argument is a value in a position this check cannot see. It is judged for
/// the worst position it could land in: a sink, which makes a URL in it a
/// request the guest chose, and a `class`, which makes brackets guest-authored
/// CSS.
fn Policy::macro_arg_refusal(self : Policy, raw : String) -> String? {
  guard macro_arg_text(raw) is Some(text) else { return None }
  if text.contains("[") || text.contains("]") {
    return Some(
      "a macro argument may not carry bracketed arbitrary utility classes; they are guest-authored CSS",
    )
  }
  guard url_shaped(text) is Some(url) else { return None }
  if !self.allows_external_urls {
    return Some(
      "a macro argument may not carry a URL: this host does not allow external URLs in views",
    )
  }
  guard origin_of(url) is Some(origin) else {
    return Some(
      "'\{text}' is a URL that pins no origin; an argument the body can concatenate has to state scheme and authority itself",
    )
  }
  self.origin_refusal(origin)
}
