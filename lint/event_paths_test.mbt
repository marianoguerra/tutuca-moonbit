// The event-path lint: what it reports, and what it leaves alone.
//
// The rule advises — the paths it names still resolve under the open profile
// an author's own views run under. The REFUSAL half of this vocabulary lives
// in `tgc/policy`, which walks the same events and refuses instead.

///|
test "an off-list traversal step is reported, naming step and site" {
  let html = "<button @on.click=\"go e.target.form.action\">x</button>"
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  let _ = @anode.ANode::parse(html, px)
  let findings = @lint.check_event_paths(px.events)
  assert_eq(findings.length(), 1)
  let f = findings[0]
  assert_true(f.code is EventPathUnsafeStep)
  assert_eq(f.level, Hint)
  assert_true(@lint.code_name(f.code) == "EVENT_PATH_UNSAFE_STEP")
  assert_eq(@lint.finding_message(f).contains("'e.target.form.action'"), true)
  assert_eq(@lint.finding_message(f).contains("traverses 'form'"), true)
}

///|
test "paths the safe profile permits are not reported" {
  let html = "<input @on.input=\"set e.value\">" +
    "<button @on.click=\"pick e.target.dataset.rowId\">r</button>" +
    "<button @on.click=\"zoom e.detail.a.b.c\">z</button>"
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  let _ = @anode.ANode::parse(html, px)
  assert_eq(@lint.check_event_paths(px.events), [])
}

///|
test "the escape path is refused at the step that leaves, not at the root" {
  // `target` is permitted; `ownerDocument` is where the walk left. The index
  // is the useful half: it says "not allowed to go that far", not "wrong
  // from the start".
  let html = "<button @on.click=\"read e.target.ownerDocument.title\">x</button>"
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  let _ = @anode.ANode::parse(html, px)
  let findings = @lint.check_event_paths(px.events)
  assert_eq(findings.length(), 1)
  fn info_of(f : @lint.Finding, key : String) -> String {
    for pair in f.info {
      if pair.0 == key {
        return pair.1
      }
    }
    ""
  }

  assert_eq(info_of(findings[0], "step"), "ownerDocument")
  assert_eq(info_of(findings[0], "index"), "1")
}
