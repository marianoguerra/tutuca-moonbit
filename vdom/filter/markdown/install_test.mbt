///| The pairing: a sanitizer gets the filters its config implies, in the order
/// that makes them mean what they say.
///
/// Two invariants live here. The first is the one this test moved from
/// `markup` with: `Policy::with_sanitizer(raw_markup: true)` is only a safe
/// thing to offer because permitting the construct also installs the filter
/// that checks it — the permission is decided in `dyncomp/policy`, a leaf over
/// anode that has no business knowing about vdom, and `filter_for` is the only
/// place the two are named together.
///
/// The second is why the function lives in THIS package: `MdFilter` is always
/// in the chain, and both replacing filters must run before the attribute
/// rules. `markup` cannot express that — it cannot import `markdown`.

///|
fn permissive() -> @sanitize.Sanitizer raise {
  @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    raw_markup: Some(true),
  })
}

///|
/// A host element carrying the RAW-HTML directive. (`host` in this package's
/// other test file carries the markdown one.)
fn html_host(payload : String) -> @vdom.Vdom {
  @vdom.h("DIV", attrs={ "dangerouslySetInnerHTML": Html(payload) })
}

// ---------------------------------------------------------------------------
// Raw markup: the permission and the filter cannot come apart

///|
/// The whole point: with raw markup permitted, the payload is parsed and
/// sanitized into children, and the directive `set_prop` looks for is gone.
test "a permissive sanitizer gets a filter that handles raw markup" {
  let tree = html_host("<p>hi <script>alert(1)</script><b>there</b></p>")
  filter_for(permissive()).filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  // Never handed to set_inner_html — the attribute it keys on is gone.
  debug_inspect(el.attrs.contains(@markup.RAW_ATTR), content="false")
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
  let tree = html_host("<p>hi</p>")
  filter_for(@sanitize.Sanitizer::default()).filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  // Untouched: the directive is still there, so `set_prop` will do what it has
  // always done. That is correct — a guest carrying this never registered, and
  // an app that wants it opts in.
  debug_inspect(el.attrs.contains(@markup.RAW_ATTR), content="true")
}

// ---------------------------------------------------------------------------
// Markdown: no permission to read, so it is always there

///|
/// The asymmetry with raw markup, stated as a test. There is no config field to
/// consult because there is nothing unchecked to permit — a markdown payload
/// becomes elements only through this same sanitizer. Omitting the filter would
/// not tighten anything; it would just make the directive render nothing.
test "markdown is handled under the default sanitizer, with no permission" {
  let tree = host("# hi\n")
  filter_for(@sanitize.Sanitizer::default()).filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(MD_ATTR), content="false")
  inspect(
    shape(tree),
    content=(
      #|<DIV><H1>hi</H1></DIV>
    ),
  )
}

///|
/// ...and it is still there on the other branch, so turning raw markup on does
/// not silently change what markdown does.
test "markdown is handled under a permissive sanitizer too" {
  let tree = host("# hi\n")
  filter_for(permissive()).filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><H1>hi</H1></DIV>
    ),
  )
}

///|
/// The config still bites, through the same chain — this is the lever a host
/// has over markdown, in place of a permission.
test "an element rule reaches markdown through the chain" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    remove_elements: Some([@sanitize.html("h1")]),
  })
  let tree = host("# gone\n\nkept\n")
  filter_for(s).filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>kept</P></DIV>
    ),
  )
}

// ---------------------------------------------------------------------------
// Order

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
  let tree = html_host("<a href=\"javascript:alert(1)\" title=\"t\">x</a>")
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

///|
/// The same claim for the markdown filter, which is the newer half of the
/// ordering. `MdFilter` checks its own output, so this passes even if the chain
/// were mis-ordered — which is exactly why the report is asserted too: a
/// `Baseline` that never saw the subtree would still leave the tree correct but
/// would not be doing the job the order exists for.
test "markdown runs before the attribute rules" {
  let tree = host("[x](javascript:alert(1))\n")
  let f = filter_for(@sanitize.Sanitizer::default())
  f.filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P><A>x</A></P></DIV>
    ),
  )
  let reports = f.take_reports().map(@filter.Dropped::to_string)
  assert_true(reports.iter().any(r => r.contains("href")))
}

///|
/// Both directives on one element. They are different attributes handled by
/// different filters, and each clears the element's children before writing its
/// own — so the LAST one in the chain wins, which is markdown. Not a
/// configuration anyone should write; the test is here so the behaviour is
/// decided rather than emergent, and so that a future reordering of the chain
/// has to notice it changed.
test "both directives on one element resolve deterministically" {
  let tree = @vdom.h("DIV", attrs={
    "dangerouslySetInnerHTML": Html("<b>html</b>"),
    "setInnerMd": Md("*md*"),
  })
  filter_for(permissive()).filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P><EM>md</EM></P></DIV>
    ),
  )
}
