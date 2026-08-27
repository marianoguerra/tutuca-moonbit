// LintCollector: the ParseHandler that records parse issues and attribute
// records for post-parse rule checks.

///|
pub fn LintCollector::new() -> LintCollector {
  { parse_issues: [], attrs: [], }
}

///|
pub impl @anode.ParseHandler for LintCollector with fn on_parse_issue(
  self,
  issue,
  current_tag,
) {
  self.parse_issues.push((issue, current_tag))
}

///|
pub impl @anode.ParseHandler for LintCollector with fn on_attributes(
  self,
  result,
  is_macro_call,
  tag,
) {
  self.attrs.push({ result, is_macro_call, tag, })
}
