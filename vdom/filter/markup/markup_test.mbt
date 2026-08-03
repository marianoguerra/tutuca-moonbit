///| Raw markup, re-admitted.
///
/// The claim under test is that a payload nobody could see at registration —
/// its value is an expression until it renders — reaches the DOM as described
/// nodes with everything the config refuses already gone, and WITHOUT ever
/// being handed to `set_inner_html`.

///|
fn host(payload : String) -> @vdom.Vdom {
  @vdom.h("DIV", attrs={ "dangerouslySetInnerHTML": Html(payload) })
}

///|
fn run(
  payload : String,
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
) -> (@vdom.Vdom, Array[String]) {
  let tree = host(payload)
  let f = MarkupFilter::new(sanitizer~)
  f.filter_tree(tree)
  (tree, f.take_reports().map(@filter.Dropped::to_string))
}

///|
/// Rendered as text, so the shape of the result is legible in one line.
fn shape(v : @vdom.Vdom) -> String {
  match v {
    Text(s) => s
    Comment(s) => "<!--\{s}-->"
    Fragment(cs) => cs.map(shape).join("")
    Node(el) => {
      let attrs = el.attrs
        .iter()
        .map(pair => " \{pair.0}=\{pair.1.to_attr_string()}")
        .to_array()
      attrs.sort()
      let inner = el.childs.map(shape).join("")
      "<\{el.tag}\{attrs.join("")}>\{inner}</\{el.tag}>"
    }
  }
}

///|
/// The attribute is GONE, which is the point: `set_prop` looks for exactly this
/// name to call `set_inner_html`, so removing it is what guarantees the payload
/// is never parsed a second time by the browser. A second parse that disagreed
/// with this one is the mutation-XSS vector the whole approach exists to avoid.
test "the payload becomes children and the directive disappears" {
  let (tree, reports) = run("<p>hello <b>world</b></p>")
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(RAW_ATTR), content="false")
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>hello <B>world</B></P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// The baseline applies to a payload exactly as it applies to a view: it is the
/// same `Sanitizer`, so a host cannot end up with two different answers to the
/// same question.
test "the baseline holds inside a payload" {
  let (tree, reports) = run("<p>ok</p><script>alert(1)</script>")
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>ok</P></DIV>
    ),
  )
  debug_inspect(
    reports,
    content=(
      #|["dropped dangerouslySetInnerHTML on <DIV>: element is not allowed here (<script>)"]
    ),
  )
  let (tree2, reports2) = run("<div onclick=\"alert(1)\" class=\"x\">hi</div>")
  inspect(
    shape(tree2),
    content=(
      #|<DIV><DIV class=x>hi</DIV></DIV>
    ),
  )
  debug_inspect(reports2.length(), content="1")
}

///|
/// The half the config has no opinion about. Nothing else will ever walk this
/// subtree — no filter runs after the one that created it — so it is checked
/// here or nowhere.
test "URL schemes inside a payload are checked too" {
  let (tree, reports) = run(
    "<a href=\"javascript:alert(1)\" title=\"t\">go</a>",
  )
  inspect(
    shape(tree),
    content=(
      #|<DIV><A title=t>go</A></DIV>
    ),
  )
  debug_inspect(
    reports,
    content=(
      #|["dropped href on <DIV>: URL scheme is not one a view may navigate to (javascript:alert(1))"]
    ),
  )
  // ...and an ordinary link is untouched.
  let (ok, _) = run("<a href=\"/about\">go</a>")
  inspect(
    shape(ok),
    content=(
      #|<DIV><A href=/about>go</A></DIV>
    ),
  )
}

///|
/// A config narrower than the baseline applies as written — this is the same
/// `SanitizerConfig` the registration-time pass takes, so a host writes one
/// answer and gets it in both places.
test "a host's own allowlist applies to a payload" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    elements: Some([
      @sanitize.ElementRule::of(@sanitize.html("p")),
      @sanitize.ElementRule::of(@sanitize.html("em")),
    ]),
    attributes: Some([]),
  })
  let (tree, _) = run(
    "<p class=\"drop-me\">keep <em>this</em> <b>not this</b></p>",
    sanitizer=s,
  )
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>keep <EM>this</EM> </P></DIV>
    ),
  )
}

///|
/// `replaceWithChildrenElements`: the element goes, its content stays. The
/// spec's third element verdict, and the one an allow/remove pair cannot
/// express.
test "an unwrapped element keeps its content" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    replace_with_children_elements: Some([@sanitize.html("span")]),
  })
  let (tree, _) = run("<p>a <span>b</span> c</p>", sanitizer=s)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P>a b c</P></DIV>
    ),
  )
}

///|
/// Comments follow the config, the same as in a view.
test "comments in a payload follow the config" {
  let (kept, _) = run("<p>a<!-- note --></p>")
  inspect(
    shape(kept),
    content=(
      #|<DIV><P>a<!-- note --></P></DIV>
    ),
  )
  let dropped = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    comments: Some(false),
  })
  let (gone, _) = run("<p>a<!-- note --></p>", sanitizer=dropped)
  inspect(
    shape(gone),
    content=(
      #|<DIV><P>a</P></DIV>
    ),
  )
}

///|
/// Children the element also declared are replaced, not merged: that is what
/// `set_inner_html` did, and changing it would be a silent behaviour change on
/// top of a security one.
test "declared children are replaced, as innerHTML replaced them" {
  let tree = @vdom.h(
    "DIV",
    attrs={ "dangerouslySetInnerHTML": Html("<i>new</i>") },
    childs=[@vdom.h("SPAN", childs=[Text("old")])],
  )
  MarkupFilter::new().filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><I>new</I></DIV>
    ),
  )
}

///|
/// A payload nested deeper than the root is reached, and an element with no
/// payload at all is left completely alone.
test "the walk reaches a payload anywhere and touches nothing else" {
  let inner = @vdom.h("SECTION", attrs={
    "dangerouslySetInnerHTML": Html("<b>x</b>"),
  })
  let tree = @vdom.h("DIV", childs=[
    @vdom.h("P", attrs={ "class": Str("plain") }, childs=[Text("kept")]),
    inner,
  ])
  MarkupFilter::new().filter_tree(tree)
  inspect(
    shape(tree),
    content=(
      #|<DIV><P class=plain>kept</P><SECTION><B>x</B></SECTION></DIV>
    ),
  )
}

///|
/// `set_prop` reads a non-`Html` value under this name as the empty payload.
/// Matching that rather than reasoning about it keeps the two paths from
/// disagreeing about what a mistyped binding means.
test "a non-Html value under the directive is dropped" {
  let tree = @vdom.h("DIV", attrs={
    "dangerouslySetInnerHTML": Str("<b>not html</b>"),
  })
  MarkupFilter::new().filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(RAW_ATTR), content="false")
  inspect(
    shape(tree),
    content=(
      #|<DIV></DIV>
    ),
  )
}
