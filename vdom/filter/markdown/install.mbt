// Pairing the permissions with the filters that make them safe.

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
/// So: read the sanitizer, and build the filters it needs.
///
/// - `raw_markup` permitted → `MarkupFilter` at the front.
/// - `MdFilter`, always. There is no permission to read for it, because there
///   is nothing unchecked to permit: a markdown payload becomes elements only
///   through this same sanitizer. Leaving it out would not make an app safer,
///   only make `@setinnermd` render nothing (`set_prop` fails closed on the
///   attribute), which is a broken feature rather than a tightened one.
/// - `@filter.Baseline` last, always.
///
/// **Order is load-bearing, and it is the reason this function lives here
/// rather than in `markup`.** Both `MarkupFilter` and `MdFilter` REPLACE a
/// subtree, and a rule that inspects attributes has to run after the nodes it
/// is meant to inspect exist — so `Baseline` goes last, and a payload's own
/// `javascript:` URL is checked rather than skipped. (Both replacing filters
/// also check what they build themselves, since the subtree each creates is one
/// no earlier filter ever saw. Belt and braces, and cheap.) `markup` cannot
/// import `markdown` — the dependency runs the other way — so only this package
/// can name all three.
///
/// A host that wants something else builds it; this is the answer for a host
/// that wants the sanitizer it already configured to be the one that runs.
pub fn filter_for(sanitizer : @sanitize.Sanitizer) -> &@filter.VdomFilter {
  let fs : Array[&@filter.VdomFilter] = []
  if sanitizer.raw_markup {
    fs.push(@markup.MarkupFilter::new(sanitizer~))
  }
  fs.push(MdFilter::new(sanitizer~))
  fs.push(@filter.Baseline::new())
  let chained : &@filter.VdomFilter = @filter.Chain::new(fs)
  chained
}

///|
/// What `App::new` installs: `filter_for` under the baseline sanitizer.
///
/// A named function rather than the expression inline so that `app` does not
/// have to import the config model to say "the default". It has no business
/// holding a `SanitizerConfig` — a plain app never configures one, and the
/// package that does is two layers away.
pub fn default_filter() -> &@filter.VdomFilter {
  filter_for(@sanitize.Sanitizer::default())
}
