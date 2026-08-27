///| The decisions: what a host will accept from a bundle, and why.
///
/// Read this next to SECURITY.md. That document says what a bundle can reach
/// and what it cannot; this is the part of it that runs.

///|
/// How much a host is willing to believe about where a bundle came from.
///
/// The authority a host deliberately extends to a bundle. Untrusted has no
/// direct DOM network/CSS channel; Granted adds the surfaces a person
/// approved; System is app code shipped by the host.
pub(all) enum TrustTier {
  /// Shipped with the app. Everything it asks for.
  System
  /// A person said yes to this specific bundle.
  Granted
  /// Dropped on the page, or fetched from a URL nobody vetted. The default,
  /// and the one the design is FOR — a runtime-extensible catalog is only
  /// interesting if this tier is usable.
  Untrusted
} derive(Eq, Debug)

///|
/// Bounds on how large a manifest may be.
///
/// Not a security boundary — a bundle with no authority cannot do harm with a
/// big manifest — but an availability one: the host parses every view and
/// compiles every component before it renders anything, so a manifest with ten
/// thousand views is a frozen tab. Cheap to check, and it makes the failure a
/// message instead of a hang.
pub(all) struct Quotas {
  max_components : Int
  max_views_per_component : Int
  max_view_bytes : Int
  max_style_bytes : Int
  max_types : Int
} derive(Eq, Debug)

///|
/// Generous on purpose. These are meant to catch a runaway or a bomb, not to
/// second-guess an author: a real component has a handful of views and a
/// dozen types, so anything here is orders of magnitude clear of legitimate
/// use.
pub fn Quotas::default() -> Quotas {
  {
    max_components: 128,
    max_views_per_component: 32,
    max_view_bytes: 262144,
    max_style_bytes: 65536,
    max_types: 512,
  }
}

///|
pub(all) struct Policy {
  tier : TrustTier
  quotas : Quotas
  /// Whether an untrusted view may pin a `<img src>` / `<a href>` to an
  /// external origin at all — see `external_url.mbt`.
  ///
  /// Set through `allowing_external_urls`, and by `with_config` when a bound
  /// variable is an origin: binding an origin is allowing it. The flag, not
  /// `external_origins.is_empty()`, is the gate — a host that allowed
  /// external URLs with an EMPTY list allowed any `https://` origin, and a
  /// host that never allowed them has an empty list too. Only consulted for
  /// Untrusted views (`check_untrusted_view_authority` returns early above
  /// Untrusted).
  allows_external_urls : Bool
  /// Whether a bundle may ship its own CSS at all.
  ///
  /// The strict answer is no, and it is the DEFAULT for an untrusted bundle:
  /// style with the host's utility classes, which are compiled by the host and
  /// therefore cannot break out of anything. That is already what all three
  /// sample guests do, so the strict tier costs nothing real.
  allow_custom_css : Bool
  /// What a guest view is checked against at registration.
  ///
  /// The BASELINE for every tier by default — the unsafe elements, the event
  /// handlers, and no raw markup — rather than the spec's default allow-list,
  /// which is not transcribed (`@sanitize.SanitizerConfig::default`). A host
  /// that wants an allow-list, or that wants to permit raw markup, builds one
  /// with `with_sanitizer`.
  ///
  /// Stored built rather than as a `SanitizerConfig` so that validity is
  /// settled once, where a host can be told about it, instead of at every
  /// `check_view` where the only options would be raising or silently falling
  /// back.
  sanitizer : @sanitize.Sanitizer
  /// The origins an untrusted view may pin a `<img src>` / `<a href>` to, each
  /// normalized to `scheme://authority`. Only consulted when
  /// `allows_external_urls` is set; empty then means any `https://` origin.
  ///
  /// Set through `allowing_external_urls`, which is also what sets the flag:
  /// the list and the allowance are one decision and a policy holding one
  /// without the other would be a policy nobody meant to write.
  external_origins : Array[String]
  /// The variables this host BOUND, by name — see `config.mbt`. Empty means
  /// every bundle runs on its manifest's own defaults, which is the strict
  /// answer: those defaults reach the guest and never reach a view.
  ///
  /// Set through `with_config`, which is also what adds an origin among them
  /// to `external_origins` and sets `allows_external_urls` with it.
  config : Map[String, ConfigBinding]
  /// Whether a bundle's OWN `origin` defaults count as bound (see
  /// `trusting_manifest_config`). False everywhere a host did not say
  /// otherwise, because the alternative lets a manifest grant itself an
  /// origin by writing one.
  trusts_manifest_config : Bool
  /// Which rule an `@on` argument's `e.<path>` resolves under — see
  /// `@eventpath.EventPathProfile`. SAFE in every tier constructor: views are
  /// data here whoever shipped them, so an off-list traversal step refuses
  /// the bundle at registration (`check_event_paths`) AND answers `Null` at
  /// dispatch — the bridge hands the same answer to its app via
  /// `App::set_event_paths`, so nothing enforces this twice by accident.
  ///
  /// A host that wants to open its own page up loosens this deliberately,
  /// with `with_open_event_paths`.
  event_paths : @eventpath.EventPathProfile
}

///|
/// What an untrusted bundle gets: no stylesheet of its own, no external
/// URLs, default quotas. It can still declare components, ship views, hold
/// state, handle events, nest children and serve its own intents — which is
/// to say, it can still be a component. That is the claim this design is
/// making. Anything it cannot do for itself — a clock, entropy, the network —
/// it asks the host for over an intent, and the host decides per call.
///
/// `CssPolicy::payload()` is the one thing here that is not a refusal, and it is
/// new: a CONSTANT inline style or SVG presentation attribute is now read
/// rather than refused by name. See `check_untrusted_attrs`. It buys a guest
/// `fill="#1da1f2"` and `style="text-align:center"` without buying it a fetch,
/// an overlay, or a `<style>` block — and a DYNAMIC value in one of those names
/// is still refused, because nothing checks it at render time here.
pub fn Policy::untrusted() -> Policy {
  {
    tier: Untrusted,
    quotas: Quotas::default(),
    allows_external_urls: false,
    allow_custom_css: false,
    sanitizer: @sanitize.Sanitizer::default().with_css(
      @safecss.CssPolicy::payload(),
    ),
    external_origins: [],
    config: Map([]),
    trusts_manifest_config: false,
    event_paths: Safe,
  }
}

///|
/// A person said yes to this bundle: its own CSS, and the whole URL surface —
/// `check_untrusted_view_authority` returns early above Untrusted, so
/// `allows_external_urls` is inert here and stays false.
pub fn Policy::granted() -> Policy {
  {
    tier: Granted,
    quotas: Quotas::default(),
    allows_external_urls: false,
    allow_custom_css: true,
    sanitizer: @sanitize.Sanitizer::default(),
    external_origins: [],
    config: Map([]),
    trusts_manifest_config: false,
    event_paths: Safe,
  }
}

///|
/// Shipped with the app, and treated as part of it. Behaviorally the same as
/// `granted()` today; the tier label is the statement of intent, kept
/// separate so a host can say which of the two things it means.
pub fn Policy::system() -> Policy {
  {
    tier: System,
    quotas: Quotas::default(),
    allows_external_urls: false,
    allow_custom_css: true,
    sanitizer: @sanitize.Sanitizer::default(),
    external_origins: [],
    config: Map([]),
    trusts_manifest_config: false,
    event_paths: Safe,
  }
}

///|
/// One reason a bundle was refused.
///
/// `where_` names the component and view when there is one (`Counter/main`) so
/// a guest author can find it, and is empty for a decision about the bundle as
/// a whole.
pub(all) struct Refusal {
  where_ : String
  message : String
} derive(Eq, Debug)

///|
fn refusal(where_ : String, message : String) -> Refusal {
  { where_, message, }
}

///|
pub fn Refusal::to_string(self : Refusal) -> String {
  if self.where_ == "" {
    self.message
  } else {
    "\{self.where_}: \{self.message}"
  }
}

///|
/// The numbers a quota is about, which the host fills in from its parsed
/// manifest.
///
/// A small record rather than the manifest itself, so this package stays a
/// leaf: policy has to be importable BY host, which means it cannot know the
/// manifest's type. What it needs is five integers, and asking for five
/// integers is honest about that.
pub(all) struct BundleFacts {
  components : Int
  max_views : Int
  max_view_bytes : Int
  max_style_bytes : Int
  max_types : Int
} derive(Eq, Debug)

///|
pub fn Policy::check_quotas(
  self : Policy,
  facts : BundleFacts,
) -> Array[Refusal] {
  let q = self.quotas
  let out : Array[Refusal] = []
  let check = (n : Int, limit : Int, what : String) => {
    if n > limit {
      out.push(refusal("", "too many \{what}: \{n} (the limit is \{limit})"))
    }
  }
  check(facts.components, q.max_components, "components")
  check(facts.max_views, q.max_views_per_component, "views in one component")
  check(facts.max_view_bytes, q.max_view_bytes, "bytes in one view")
  check(facts.max_style_bytes, q.max_style_bytes, "bytes of style")
  check(facts.max_types, q.max_types, "declared types in one component")
  out
}

///|
/// Whether this bundle may ship the style it declared.
///
/// An untrusted bundle may not, and that is the substantive change: style with
/// the host's utility classes, which the host compiles and which therefore
/// cannot break out of anything. All three sample guests already do exactly
/// that, so the strict default costs nothing real.
///
/// A bundle at a tier that DOES allow custom CSS is still accepted unvalidated,
/// and that is a known gap rather than a decision: `Component::compile_style`
/// wraps the block by string concatenation, so a `}` inside it escapes the scope
/// selector and reaches the page around it. `allow_custom_css` is a statement
/// that someone vouched for this bundle, not that anything checked it.
///
/// The VALUE validator that would do the checking exists now
/// (`anode/sanitize/css`, and `docs/css-validator.md`), and it is what let an
/// untrusted guest state a constant inline `style` again. It is not enough for
/// this: a block is selectors and at-rules as well as declarations, and the fix
/// is to prefix each selector with the scope rather than wrap the block —
/// which is what structurally kills the breakout. The one thing in the way is
/// that a selector legitimately carries escapes, which the value validator
/// refuses outright. SECURITY.md §4 has the rest.
pub fn Policy::check_style(
  self : Policy,
  where_ : String,
  style : String,
) -> Array[Refusal] {
  if style == "" || self.allow_custom_css {
    return []
  }
  [
    refusal(
      where_, "this host takes no CSS from a bundle; style with the host's utility classes instead",
    ),
  ]
}

///|
/// Whether this host will render the compiled view.
///
/// The WHATWG Sanitizer API's config model, over the compiled tree
/// (`@sanitize`). Everything in a view is DESCRIBED — a tag, an attribute name,
/// a handler name resolved at parse time — and every one of those is a literal,
/// so an allowlist over names is COMPLETE over the described part of a view.
/// That is what makes this decidable here rather than at render.
///
/// It is not decidable for attribute VALUES: `AttrItem::Plain` carries a `Val`,
/// so what an `href` will hold is unknowable until render. For an Untrusted
/// bundle the authority check therefore refuses browser network/CSS SINKS by
/// name, alongside raw Markdown and arbitrary utility CSS. Granted/System
/// bundles retain the ordinary URL filter at render time.
pub fn Policy::check_view(
  self : Policy,
  where_ : String,
  tree : @anode.ANode,
) -> Array[Refusal] {
  let out = self.sanitizer
    .check(tree)
    .map(v => refusal(where_, @sanitize.Violation::to_string(v)))
  out.append(self.check_untrusted_view_authority(where_, tree))
  out
}

///|
/// The same policy, checking views against a different sanitizer.
///
/// Raises on an invalid config rather than degrading, because an invalid config
/// is a programming error in the HOST — the one party here who can read an
/// error message and fix it — and a sanitizer that quietly did something else
/// is the failure mode this whole area exists to avoid.
///
/// Two things a host reaches for this to do, and they pull in opposite
/// directions:
///
/// - **tighten**, with an allow-list of elements and per-element attributes.
///   The spec's default allow-list is not transcribed
///   (`@sanitize.SanitizerConfig::default`), so a host that wants one writes it
///   and gets `validate()` to keep it honest. If you do this, remember the four
///   names a config may not eat — `data-eid`, `data-cid`, `data-vid`,
///   `data-nid` — which `@sanitize` carves out ahead of any config precisely
///   because an allow-list that forgot them renders a component that then
///   responds to nothing.
/// - **loosen**, on a Granted/System policy, most usefully with
///   `raw_markup: true`. Untrusted keeps refusing it because sanitized HTML
///   may still make a network request. For a trusted tier it is only safe when
///   the render-time markup filter is installed; see
///   `@markdown.filter_for`, which is what pairs the two so a host cannot
///   have the permission without the filter.
/// The same policy, with CSS narrowed or widened.
///
/// Separate from `with_sanitizer` because a `SanitizerConfig` says nothing
/// about CSS — the Sanitizer API's vocabulary is names, and every question here
/// lives in a value. A host tightening its element allow-list must not thereby
/// widen what a guest may paint with, which is why `with_sanitizer` carries the
/// CSS policy across rather than taking the compiled sanitizer's default.
pub fn Policy::with_css(self : Policy, css : @safecss.CssPolicy) -> Policy {
  { ..self, sanitizer: self.sanitizer.with_css(css), }
}

///|
pub fn Policy::with_sanitizer(
  self : Policy,
  config : @sanitize.SanitizerConfig,
) -> Policy raise @sanitize.InvalidConfig {
  // The CSS policy is carried across rather than reset. A config has no field
  // for it, so taking the freshly compiled sanitizer's default would silently
  // widen an untrusted policy from `payload()` to `app()` — a host tightening
  // its element allow-list would be loosening its CSS in the same call.
  {
    ..self,
    sanitizer: @sanitize.Sanitizer::new(config).with_css(self.sanitizer.css),
  }
}

///|
/// Whether a guest view may use `@dangerouslysetinnerhtml`.
///
/// False everywhere by default, and always false for Untrusted: even sanitized
/// HTML can contain a non-script network request. A trusted host that flips it
/// MUST also install the
/// markup filter — the payload is a `Val` at registration, so nothing decided
/// here can see what it will hold, and without the filter it goes to
/// `set_inner_html` unchecked. `@markdown.filter_for` reads this and builds the
/// matching filter, which is how the two stay in step.
pub fn Policy::allows_raw_markup(self : Policy) -> Bool {
  self.tier != Untrusted && self.sanitizer.raw_markup
}
