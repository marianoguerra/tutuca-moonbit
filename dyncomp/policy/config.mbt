///| What a bundle's variables are, once a host has decided them.
///
/// A config var is the answer to "this component would work anywhere, if
/// somebody told it where." `guests/mastodon` is the worked example: the same
/// six components read mastodon.social or hachyderm.io depending on two
/// strings, and neither the wasm nor the views change between them.
///
/// The whole design is one question — WHO chose the string — and the answer
/// has to be the host for the same reason it has to be the host in
/// `external_url.mbt`. A manifest DECLARES a variable, with a default and a
/// type; a host BINDS it. The default is what the guest reads when nobody
/// bound anything, and it is deliberately not enough to open a URL sink: a
/// bundle that could grant itself an origin by writing one in its own manifest
/// would make the origin rule decorative.
///
/// So the type is stated TWICE, once by each party, and they have to agree.
/// That is not belt-and-braces, it is the actual boundary: without the host's
/// half, a manifest could declare `type: "origin"` for a variable the host
/// bound as ordinary prose — an internal API base, say — and turn a string the
/// host meant as data into a network grant. `Policy::with_config` therefore
/// takes typed values, and a declaration that disagrees refuses the bundle.

///|
/// What a config value is allowed to be, which is what decides where it may
/// land.
pub(all) enum ConfigTy {
  /// An `http(s)` origin, complete through the `/` that ends the authority.
  /// The ONLY type a view can read: `$$name` resolves to a literal, and a
  /// literal in a `<img src>` / `<a href>` head is a pinned origin.
  TyOrigin
  /// A string. Guest-side only — prose, a label, a server's name as a person
  /// writes it. Never reachable from a view, because a `Const` the URL rule
  /// would pin is exactly what it must not become.
  TyText
  TyBool
  TyNumber
} derive(Eq, Debug)

///|
pub fn ConfigTy::to_string(self : ConfigTy) -> String {
  match self {
    TyOrigin => "origin"
    TyText => "text"
    TyBool => "bool"
    TyNumber => "number"
  }
}

///|
/// `None` for a name this host does not know, kept rather than defaulted for
/// the reason `Capability::parse` keeps `CapUnknown`: a type that silently
/// became `text` would read as a policy that was applied.
pub fn ConfigTy::parse(s : String) -> ConfigTy? {
  match s {
    "origin" => Some(TyOrigin)
    "text" => Some(TyText)
    "bool" => Some(TyBool)
    "number" => Some(TyNumber)
    _ => None
  }
}

///|
/// One bound variable: what the host says it is, and what the host says it is
/// worth.
///
/// The value is a String at every type, because a String is what crosses to
/// the guest (`config.get`) and what lands in a view (`$$name`). `TyBool` and
/// `TyNumber` are about the SPELLING being one a guest can parse back, not
/// about carrying a different runtime type.
pub(all) struct ConfigBinding {
  ty : ConfigTy
  value : String
} derive(Eq, Debug)

///|
/// An origin the host binds: normalized to `scheme://authority/` and checked
/// the way `allowing_external_urls` checks its list, because it ends up in the
/// same place.
pub fn origin(value : String) -> ConfigBinding {
  { ty: TyOrigin, value }
}

///|
pub fn text(value : String) -> ConfigBinding {
  { ty: TyText, value }
}

///|
pub fn bool_(value : Bool) -> ConfigBinding {
  { ty: TyBool, value: if value { "true" } else { "false" } }
}

///|
pub fn number(value : Double) -> ConfigBinding {
  { ty: TyNumber, value: value.to_string() }
}

///|
/// A config value that is not what its type says it is.
///
/// Loud rather than lenient, and for a sharper reason than `InvalidOrigin`:
/// the value came from the HOST, so a bad one is a line of host code somebody
/// can fix, and a config var that silently fell back to its manifest default
/// would be a host that thought it had pointed a bundle somewhere and had not.
pub suberror InvalidConfig {
  InvalidConfig(Array[String])
}

///|
pub fn InvalidConfig::to_string(self : InvalidConfig) -> String {
  let InvalidConfig(bad) = self
  "bad config bindings: \{bad.join("; ")}"
}

///|
/// Why this value is not the type it claims, or None when it is.
fn binding_refusal(name : String, b : ConfigBinding) -> String? {
  match b.ty {
    TyOrigin =>
      match normalized_origin(b.value) {
        Some(_) => None
        None =>
          Some(
            "'\{name}' is an origin, so it has to be a complete http(s) origin like 'https://cdn.example' — '\{b.value}' is not",
          )
      }
    // A text value is never re-read by anything that parses, so there is
    // nothing here to be wrong. It is listed rather than defaulted so adding a
    // type makes this match fail to compile.
    TyText => None
    TyBool =>
      if b.value is ("true" | "false") {
        None
      } else {
        Some(
          "'\{name}' is a bool, so it is 'true' or 'false', not '\{b.value}'",
        )
      }
    TyNumber =>
      if reads_as_number(b.value) {
        None
      } else {
        Some("'\{name}' is a number, and '\{b.value}' does not read as one")
      }
  }
}

///|
fn reads_as_number(value : String) -> Bool {
  let _ : Double = @string.parse_double(value) catch { _ => return false }
  true
}

///|
/// The same policy, with these variables bound — and, for every origin among
/// them, the `cap-external-urls` grant that binding one MEANS.
///
/// One call rather than a binding step and a grant step, for the reason
/// `allowing_external_urls` gives: they are one decision. A host that says
/// "this bundle's pictures are on files.hachyderm.io" has said the bundle may
/// load pictures from files.hachyderm.io, and a version of this that made you
/// say it twice would mostly produce hosts that said it once.
///
/// The consequence, stated plainly because it is the sharp edge: **binding an
/// origin is granting it.** A host that binds one from input it did not write
/// — a query parameter, a model's output — has granted whatever that input
/// named. `origin_of` still refuses anything that is not a well-formed http(s)
/// authority, so the worst case is a picture fetched from a server the input
/// chose; it is not a way past the rule, but it is a real decision and it
/// belongs in host code that means it. See SECURITY.md §3.
///
/// A path in an origin is dropped rather than honored, exactly as it is in
/// `allowing_external_urls` and for the same reason: `/public/../private/key`
/// is a URL to `/private/key`, so a path prefix is not a boundary.
pub fn Policy::with_config(
  self : Policy,
  bindings : Array[(String, ConfigBinding)],
) -> Policy raise InvalidConfig {
  let bad : Array[String] = []
  let config : Map[String, ConfigBinding] = Map([])
  let origins : Array[String] = [..self.external_origins]
  for entry in bindings {
    let (name, b) = entry
    if config.contains(name) {
      bad.push("'\{name}' is bound twice")
      continue
    }
    match binding_refusal(name, b) {
      Some(why) => {
        bad.push(why)
        continue
      }
      None => ()
    }
    match b.ty {
      TyOrigin => {
        // Normalized here rather than at use: what the view interpolates and
        // what `origin_refusal` compares have to be the same string, and the
        // trailing `/` is what closes the authority so a path cannot re-point
        // it. `guest.media_path` strips the same string on the other side.
        guard origin_of(with_authority_end(b.value)) is Some(bare) else {
          continue
        }
        // Two spellings, and they are not interchangeable: a view needs the
        // closing `/` so its template pins, and `external_origins` holds what
        // `origin_of` returns, which is what `origin_refusal` compares.
        config[name] = { ty: TyOrigin, value: bare + "/" }
        if !origins.contains(bare) {
          origins.push(bare)
        }
      }
      _ => config[name] = b
    }
  }
  if !bad.is_empty() {
    raise InvalidConfig(bad)
  }
  let grants = if origins.is_empty() || self.grants.contains(CapExternalUrls) {
    self.grants
  } else {
    [..self.grants, CapExternalUrls]
  }
  { ..self, grants, external_origins: origins, config }
}

///|
/// Accept the bundle's OWN origin defaults as if the host had bound them.
///
/// For a page that ships the bundles it loads — the storybook, the demo shell,
/// a guest's test harness — where "the manifest's default" and "what this page
/// decided" are the same sentence, and writing the origins out a second time
/// in host code would only be a chance to disagree with them.
///
/// It is a separate call, and named for what it costs, because it is the one
/// case where a bundle's own file decides an origin. Do not reach for it on a
/// page that loads bundles it did not ship: there, deciding per bundle is the
/// entire point of the capability, and `with_config` is where that decision
/// goes.
pub fn Policy::trusting_manifest_config(self : Policy) -> Policy {
  { ..self, trusts_manifest_config: true }
}

///|
/// What `$$name` resolves to in this bundle's views: the ORIGINS and nothing
/// else.
///
/// The narrowing is the enforcement `ConfigTy` describes. A `$$name` resolves
/// to a `Const` the URL rule will happily pin, so a text variable reachable
/// from a view would be a text variable that could be an origin. Leaving them
/// out of the table means a view naming one gets `BadConfigVar` — a sentence
/// about a name that was not bound, which is exactly what happened.
pub fn Policy::view_config(self : Policy) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for name, b in self.config {
    if b.ty is TyOrigin {
      out[name] = b.value
    }
  }
  out
}
