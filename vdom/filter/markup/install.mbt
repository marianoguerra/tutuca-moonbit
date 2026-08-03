// Pairing the permission with the filter that makes it safe.

///|
/// The render-time filter a sanitizer implies.
///
/// This exists so that "a config permits raw markup" and "the filter that
/// checks raw markup is installed" cannot come apart. They are two decisions in
/// two layers — the config is settled at registration, in a package that has no
/// business knowing about vdom, while the filter is installed on an `App` — and
/// keeping them in step by remembering to is exactly the kind of invariant that
/// holds until the day it does not.
///
/// So: read the sanitizer, and build the filter it needs.
///
/// - `raw_markup` permitted → `MarkupFilter` in FRONT of `@filter.Baseline`.
///   The order is load-bearing: the markup filter REPLACES a subtree, and a
///   rule that inspects attributes has to run after the nodes it is meant to
///   inspect exist. (`MarkupFilter` also checks what it builds itself, since
///   the subtree it creates is one no earlier filter ever saw — belt and
///   braces, and cheap.)
/// - not permitted → `@filter.Baseline` alone. Building the markup filter would
///   cost a walk per render to look for a construct that is refused at
///   registration and therefore cannot be there.
///
/// A host that wants something else builds it; this is the answer for a host
/// that wants the sanitizer it already configured to be the one that runs.
pub fn filter_for(sanitizer : @sanitize.Sanitizer) -> &@filter.VdomFilter {
  if sanitizer.raw_markup {
    let chained : &@filter.VdomFilter = @filter.Chain::new([
      MarkupFilter::new(sanitizer~),
      @filter.Baseline::new(),
    ])
    chained
  } else {
    let baseline : &@filter.VdomFilter = @filter.Baseline::new()
    baseline
  }
}
