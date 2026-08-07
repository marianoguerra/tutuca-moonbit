///|
/// The render-time filter a sanitizer implies — the raw-markup half of it.
///
/// @deprecated Use `@markdown.filter_for`, which is the same function with the
/// markdown filter in the chain. This one cannot install it: the dependency
/// runs `markdown` → `markup` and never back, so this package has no way to
/// name `MdFilter`. An app wired through here renders `@setinnermd` as an empty
/// element (`set_prop` fails closed on the attribute) — not unsafely, but not
/// usefully either.
///
/// Kept because it is still the right answer for a host that deliberately wants
/// the raw-markup rule and the baseline and nothing else.
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
