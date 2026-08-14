///| Something a component cannot do for itself, and the host can.
///
/// Requested by a manifest, granted by a policy. There is no negotiation and
/// no partial grant, because a capability that is present but lies is worse
/// than one that is absent: a guest that reads a frozen zero from an ungranted
/// clock cannot tell that from midnight.
///
/// `control.request` is deliberately absent from this list. Whether a guest
/// may reach a HOST request handler is a decision about the CALLER, made per
/// call from the requester's path, not a claim read out of a manifest — see
/// SECURITY.md §5.

///|
pub(all) enum Capability {
  /// env.now-ms, env.tz-offset-min, env.locale
  CapClock
  /// env.random-u64, env.new-id
  CapRandom
  /// control.after
  CapTimer
  /// `src` on `<img>` and `href` on `<a>`, pointing at an absolute URL whose
  /// ORIGIN is a literal in the view (`Policy::allowing_external_urls`).
  ///
  /// The one capability that is about the view rather than about an import,
  /// and the only one a guest cannot detect the absence of by calling
  /// something: an untrusted bundle without it is refused at registration
  /// rather than served a lie at runtime, which is the same bargain the
  /// others make.
  ///
  /// It is a NETWORK grant and reads as one: an image the guest chooses is a
  /// request the guest chooses, to an origin that learns the page loaded it.
  /// Pinning the origin in the view is what keeps that origin the host's
  /// decision instead of the guest's — see SECURITY.md §3.
  ///
  /// A view can also reach the origin through a config var (`$$name`,
  /// `config.mbt`), and the bargain there is the same one read from the other
  /// end: **binding an origin is granting it.** `Policy::with_config` adds this
  /// capability for exactly that reason, so a host that pointed a bundle at a
  /// CDN does not then have to remember to permit the CDN.
  CapExternalUrls
  /// A name this host does not know. Kept rather than dropped so a refusal can
  /// SAY which one: a dropped name would make a bundle asking for something
  /// unrecognized look like a bundle asking for nothing.
  CapUnknown(String)
} derive(Eq, Debug)

///|
pub fn Capability::to_string(self : Capability) -> String {
  match self {
    CapClock => "cap-clock"
    CapRandom => "cap-random"
    CapTimer => "cap-timer"
    CapExternalUrls => "cap-external-urls"
    CapUnknown(s) => s
  }
}

///|
pub fn Capability::parse(s : String) -> Capability {
  match s {
    "cap-clock" => CapClock
    "cap-random" => CapRandom
    "cap-timer" => CapTimer
    "cap-external-urls" => CapExternalUrls
    other => CapUnknown(other)
  }
}

///|
pub(all) struct CapabilityReq {
  cap : Capability
  /// Why the bundle needs it, shown to whoever decides. A request with no
  /// reason is a request a person cannot judge, which is the whole difficulty
  /// with permission prompts everywhere else.
  reason : String
} derive(Eq, Debug)
