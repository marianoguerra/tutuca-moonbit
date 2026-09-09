// Optional Markdown rendering and a complete chain for standalone VDOM users.

///|
/// Pass this factory as `markdown_filter` when constructing an app.
/// Payload CSS is narrowed each time the app supplies its sanitizer.
pub fn make_filter(sanitizer : @sanitize.Sanitizer) -> &@filter.VdomFilter {
  MdFilter::new(sanitizer=sanitizer.with_css(@safecss.CssPolicy::payload()))
}

///|
/// Filter a standalone tree with markup, Markdown and the mandatory baseline.
pub fn filter_for(sanitizer : @sanitize.Sanitizer) -> &@filter.VdomFilter {
  @markup.filter_for(sanitizer, markdown_filter=make_filter)
}

///|
pub fn default_filter() -> &@filter.VdomFilter {
  filter_for(@sanitize.Sanitizer::default())
}
