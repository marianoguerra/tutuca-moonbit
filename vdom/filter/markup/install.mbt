// The mandatory filter chain, with an optional Markdown renderer.

///|
pub fn filter_for(
  sanitizer : @sanitize.Sanitizer,
  markdown_filter? : (@sanitize.Sanitizer) -> &@filter.VdomFilter,
) -> &@filter.VdomFilter {
  let fs : Array[&@filter.VdomFilter] = []
  if sanitizer.raw_markup {
    fs.push(MarkupFilter::new(sanitizer~))
  }
  fs.push(SafeMarkupFilter::new(sanitizer~))
  match markdown_filter {
    Some(make) => fs.push(make(sanitizer))
    None => fs.push(MissingMarkdown::{ log: @filter.DropLog::new(), })
  }
  fs.push(@filter.Baseline::new())
  @filter.Chain::new(fs)
}

///|
priv struct MissingMarkdown {
  log : @filter.DropLog
}

///|
impl @filter.VdomFilter for MissingMarkdown with fn filter_elem(self, el) {
  if el.attrs.get("setInnerMd") is Some(value) {
    el.attrs.remove("setInnerMd")
    el.childs.clear()
    self.log.record({
      tag: el.tag,
      attr: "setInnerMd",
      value: match value {
        Md(source) => source
        _ => ""
      },
      reason: "configure markdown_filter=@markdown.make_filter when mounting this app",
    })
  }
}

///|
impl @filter.VdomFilter for MissingMarkdown with fn take_reports(self) {
  self.log.take()
}
