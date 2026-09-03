///| Turning a module's DECLARED variables and a host's BOUND ones into the two
/// tables a registration runs on.
///
/// The manifest half is a declaration — a name, a type, a default and a
/// sentence — and the policy half is a decision. Neither is enough alone, and
/// the seam between them is where the security argument lives: see
/// `@policy.with_config` for why both state the type.

///|
/// What a module actually runs with, in the two shapes the two consumers need.
pub(all) struct ResolvedConfig {
  /// Every variable, by name — what the GUEST reads through `config.get`.
  /// Declared defaults included, because a module nobody configured should
  /// still be the thing its author shipped.
  all : Map[String, String]
  /// What a VIEW may name with `host.name`: the origins, and only the ones a host
  /// stands behind. A text variable is absent because a `host.name` becomes a
  /// literal and a literal can pin a URL; an unbound origin default is absent
  /// because a module that could name its own origin would make the rule in
  /// `external_url.mbt` decorative.
  view : Map[String, String]
} derive(Debug, Eq)

///|
/// A stable serialization of the resolved config: names sorted, so two hosts
/// that bound the same things in a different order get the same string.
///
/// The separators are characters a name cannot contain (a name is a value id —
/// letters, digits, `_`) so no pair of distinct configs can collide by writing
/// their contents next to each other.
fn ResolvedConfig::canonical(self : ResolvedConfig) -> String {
  let names = self.all.keys().collect()
  names.sort()
  let sb = StringBuilder()
  for name in names {
    sb.write_string("\{name}=\{self.all.get(name).unwrap_or("")}\n")
  }
  sb.to_string()
}

///|
/// The module's declarations with the host's bindings applied, plus the policy
/// that decision implies.
///
/// Returns a POLICY as well as a config because `trusting_manifest_config`
/// cannot be resolved anywhere else: it says "this module's own origin
/// defaults count as bound", and what that means concretely is that those
/// origins join `external_origins` — which only the manifest, in hand here,
/// can supply.
///
/// Three ways this refuses, and one way it only complains:
///
/// - a bound value whose type disagrees with the declaration. This is the
///   security-relevant one: without it a manifest could declare `origin` for
///   something a host bound as prose and turn a string into a network grant.
/// - a declared `origin` whose own default is not an origin, when the host
///   asked to trust those defaults — it asked for something that does not
///   exist.
/// - a `host.name` in a view that resolves to nothing, which the parser reports
///   on its own (`BadConfigVar`) and `screen_view` surfaces.
///
/// A host that binds a name this module does not declare gets a DIAGNOSTIC
/// rather than a refusal, and the asymmetry is deliberate: one policy is
/// normally shared across every module a page loads, so "bound but not
/// declared here" is the ordinary case for all but one of them. It is still
/// worth saying, because the other reason to see it is a typo.
fn resolve_config(
  manifest : DynManifest,
  policy : @policy.Policy,
  into : Array[String],
) -> (ResolvedConfig, @policy.Policy) raise ManifestError {
  let all : Map[String, String] = Map([])
  let view : Map[String, String] = Map([])
  let manifest_origins : Array[String] = []
  for def in manifest.config {
    match policy.config.get(def.name) {
      Some(b) => {
        guard b.ty == def.ty else {
          raise ManifestError(
            "module refused: config '\{def.name}' is declared '\{def.ty.to_string()}' and this host bound it as '\{b.ty.to_string()}'",
          )
        }
        all[def.name] = b.value
        if def.ty is TyOrigin {
          // Already normalized through the `/` that ends the authority by
          // `with_config`, and already in `external_origins` — this only says
          // the views may reach it.
          view[def.name] = b.value
        }
      }
      None => {
        all[def.name] = def.default_
        if def.ty is TyOrigin && policy.trusts_manifest_config {
          guard @policy.normalized_origin(def.default_) is Some(o) else {
            raise ManifestError(
              "module refused: this host trusts manifest config, and config '\{def.name}' defaults to '\{def.default_}', which is not an http(s) origin",
            )
          }
          view[def.name] = o
          manifest_origins.push(o)
        }
      }
    }
  }
  for name in policy.config.keys() {
    if !all.contains(name) {
      into.push(
        "CONFIG-UNDECLARED (info) : this host bound '\{name}', which this module does not declare",
      )
    }
  }
  let effective = if manifest_origins.is_empty() {
    policy
  } else {
    policy.allowing_external_urls(
      [..policy.external_origins, ..manifest_origins],
    ) catch {
      // Unreachable: every entry came back from `normalized_origin` above.
      // Re-raised rather than swallowed so a future change that breaks that
      // invariant is a message instead of a silently narrower policy.
      e =>
        raise ManifestError(
          "module refused: manifest config origins: \{e.to_string()}",
        )
    }
  }
  ({ all, view, }, effective)
}
