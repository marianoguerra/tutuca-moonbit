///| The pairing: a sanitizer that permits raw markup gets the filter that
/// checks it, and one that does not is not made to pay for it.
///
/// This is the test that makes `Policy::with_sanitizer(raw_markup: true)` a
/// safe thing to offer. The permission is decided in `dyncomp/policy`, a leaf
/// over anode that has no business knowing about vdom; the filter is installed
/// on an `App`. Two layers, one invariant, and `filter_for` is the only place
/// it is expressed.

///|
fn permissive() -> @sanitize.Sanitizer raise {
  @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    raw_markup: Some(true),
  })
}

///|
/// The whole point: with raw markup permitted, the payload is parsed and
/// sanitized into children, and the directive `set_prop` looks for is gone.
test "a permissive sanitizer gets a filter that handles raw markup" {
  let tree = host("<p>hi <script>alert(1)</script><b>there</b></p>")
  filter_for(permissive()).filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  // Never handed to set_inner_html — the attribute it keys on is gone.
  debug_inspect(el.attrs.contains(RAW_ATTR), content="false")
  // ...and permitting the CONSTRUCT is not permitting its contents: the
  // baseline still ate the script.
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>hi <B>there</B></P></DIV>
    ),
  )
}

///|
/// The default direction. Building a markup filter here would cost a walk per
/// render looking for a construct that registration already refuses.
test "a baseline sanitizer gets no markup filter" {
  let tree = host("<p>hi</p>")
  filter_for(@sanitize.Sanitizer::default()).filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  // Untouched: the directive is still there, so `set_prop` will do what it has
  // always done. That is correct — a guest carrying this never registered, and
  // an app that wants it opts in.
  debug_inspect(el.attrs.contains(RAW_ATTR), content="true")
}

///|
/// Both filters carry the baseline rules, so the URL and handler checks do not
/// depend on which branch was taken. A host that permits raw markup must not
/// quietly lose the rules it did not ask to change.
test "the baseline rules run either way" {
  for sanitizer in [@sanitize.Sanitizer::default(), permissive()] {
    let tree : @vdom.Vdom = @vdom.h("DIV", childs=[
      @vdom.h("A", attrs={
        "href": Str("javascript:alert(1)"),
        "onclick": Str("alert(2)"),
        "title": Str("kept"),
      }),
    ])
    filter_for(sanitizer).filter_tree(tree)
    guard tree is Node(el) else { fail("expected an element") }
    guard el.childs[0] is Node(a) else { fail("expected an element") }
    assert_true(a.attrs.get("href") is None)
    assert_true(a.attrs.get("onclick") is None)
    assert_true(a.attrs.get("title") is Some(Str("kept")))
  }
}

///|
/// Order is load-bearing, not incidental: the markup filter REPLACES a subtree,
/// so a rule that inspects attributes has to run after the nodes it inspects
/// exist. A chain built the other way round would let a payload's own
/// `javascript:` URL through.
test "markup runs before the attribute rules" {
  let tree = host("<a href=\"javascript:alert(1)\" title=\"t\">x</a>")
  let f = filter_for(permissive())
  f.filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><A title=t>x</A></DIV>
    ),
  )
  // Reported through the chain, so a host draining one log sees it.
  let reports = f.take_reports().map(@filter.Dropped::to_string)
  assert_true(reports.length() >= 1)
  assert_true(reports.iter().any(r => r.contains("href")))
}
