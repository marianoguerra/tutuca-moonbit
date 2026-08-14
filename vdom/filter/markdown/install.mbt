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
/// - `@markup.SafeMarkupFilter`, always, for the same reason `MdFilter` is
///   always here: `set_prop` fails closed on `@setinnerhtml` and
///   `@setinnersvg`, so there is no unchecked path to permit and leaving it out
///   only breaks the directives. See `markup/safe.mbt` for why that is a
///   different situation from `@dangerouslysetinnerhtml` rather than the same
///   one with the check removed.
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
  fs.push(@markup.SafeMarkupFilter::new(sanitizer~))
  // Narrowed here, once, which it could not be before. The narrowing available
  // used to be `without_css`, which dropped `style` by NAME — and the only
  // `style` markdown emits is GFM's column alignment, `text-align:left`, which
  // `build.mbt` writes itself. Narrowing the whole filter took both, so
  // `build.mbt` carried two sanitizers and applied the narrow one only where it
  // handed a payload to `@markup.html_nodes`.
  //
  // `CssPolicy::payload()` reads the VALUE, so it does not need to know who
  // wrote it: the alignment is admitted at the smallest level there is, and a
  // `url(…)` is admitted at none. A markdown document is content the app did not
  // write — that is what `@setinnermd` is FOR — so the whole walk gets the
  // payload policy and `build.mbt` carries one sanitizer again.
  fs.push(
    MdFilter::new(sanitizer=sanitizer.with_css(@safecss.CssPolicy::payload())),
  )
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
