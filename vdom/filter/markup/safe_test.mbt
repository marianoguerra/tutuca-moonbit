///| `@setinnerhtml` and `@setinnersvg`, the markup directives whose names carry
/// no warning.
///
/// Two claims under test. That a payload nobody could see at registration
/// reaches the DOM as described nodes with everything the config refuses gone —
/// the same claim `markup_test.mbt` makes about the dangerous directive, re-run
/// here because a safe NAME is a promise and a promise wants a test. And, for
/// the SVG half, that the namespace is a guarantee rather than a request: what
/// the payload asked to be does not decide what it becomes.

///|
fn safe_host(attr : String, value : @vdom.AttrValue) -> @vdom.Vdom {
  @vdom.h("DIV", attrs=Map::from_array([(attr, value)]))
}

///|
fn run_html(
  payload : String,
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
) -> (@vdom.Vdom, Array[String]) {
  let tree = safe_host(SAFE_HTML_ATTR, SafeHtml(payload))
  let f = SafeMarkupFilter::new(sanitizer~)
  f.filter_tree(tree)
  (tree, f.take_reports().map(@filter.Dropped::to_string))
}

///|
fn run_svg(
  payload : String,
  sanitizer? : @sanitize.Sanitizer = @sanitize.Sanitizer::default(),
) -> (@vdom.Vdom, Array[String]) {
  let tree = safe_host(SAFE_SVG_ATTR, Svg(payload))
  let f = SafeMarkupFilter::new(sanitizer~)
  f.filter_tree(tree)
  (tree, f.take_reports().map(@filter.Dropped::to_string))
}

///|
/// The first `attr` found anywhere in the tree, or `"-"`.
///
/// For the CSS tests, which are about what a value BECAME rather than about the
/// shape of the tree it sits in.
fn attr_of(v : @vdom.Vdom, attr : String) -> String {
  match v {
    Node(el) => {
      match el.attrs.get(attr) {
        Some(value) => return value.to_attr_string()
        None => ()
      }
      for child in el.childs {
        let found = attr_of(child, attr)
        if found != "-" {
          return found
        }
      }
      "-"
    }
    Fragment(cs) => {
      for child in cs {
        let found = attr_of(child, attr)
        if found != "-" {
          return found
        }
      }
      "-"
    }
    _ => "-"
  }
}

///|
/// Like `shape`, but printing the namespace, which is the whole subject of the
/// SVG half and which `shape` deliberately drops.
fn ns_shape(v : @vdom.Vdom) -> String {
  match v {
    Text(s) => s
    Comment(s) => "<!--\{s}-->"
    Fragment(cs) => cs.map(ns_shape).join("")
    Node(el) => {
      let prefix = match el.ns {
        None => ""
        Some(Svg) => "svg:"
        Some(MathMl) => "math:"
        Some(Other(u)) => u + ":"
      }
      let attrs = el.attrs
        .iter()
        .map(pair => " \{pair.0}=\{pair.1.to_attr_string()}")
        .to_array()
      attrs.sort()
      let inner = el.childs.map(ns_shape).join("")
      "<\{prefix}\{el.tag}\{attrs.join("")}>\{inner}</\{prefix}\{el.tag}>"
    }
  }
}

// ---------------------------------------------------------------------------
// @setinnerhtml

///|
/// The attribute is GONE, which is what makes the directive safe rather than
/// merely filtered: `set_prop` looks for exactly this name, and finding it
/// CLEARS the element (`vdom/to_dom.mbt`). Removing it here is the difference
/// between "the payload rendered" and "the payload rendered as nothing".
test "setinnerhtml becomes children and the directive disappears" {
  let (tree, reports) = run_html("<p>hello <b>world</b></p>")
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(SAFE_HTML_ATTR), content="false")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><P>hello <B>world</B></P></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// Declared children lose, the way they do under `set_inner_html` and under the
/// other two replacing directives. Nothing new here; pinned so a refactor that
/// made the payload append instead of replace would be caught.
test "setinnerhtml replaces declared children" {
  let tree = @vdom.h(
    "DIV",
    attrs=Map::from_array([(SAFE_HTML_ATTR, SafeHtml("<i>payload</i>"))]),
    childs=[@vdom.h("SPAN", childs=[Text("declared")])],
  )
  SafeMarkupFilter::new().filter_tree(tree)
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><I>payload</I></DIV>
    ),
  )
}

///|
/// The unsafe baseline, which no config can switch off, reached through the
/// safe name. The report names the directive the author wrote — not
/// `dangerouslySetInnerHTML`, which is the shared builder's own constant and
/// appears nowhere in this view.
test "setinnerhtml refuses the baseline and says which directive" {
  let (tree, reports) = run_html("ok<script>alert(1)</script>")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV>ok</DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerHtml on <DIV>: element is not allowed here (<script>)
    ),
  )
}

///|
/// The two halves of the URL rule that the Sanitizer API declines to answer.
/// `java&#9;script:` is the interesting one: it is safe here because
/// `parse_fragment` is a real HTML parser and decodes the entity to a tab
/// BEFORE anything looks at the value, and then `scheme_of` strips the tab.
/// Neither step alone would do.
///
/// A denied URL drops the ATTRIBUTE, not the element — the link keeps its words
/// and loses its destination.
test "setinnerhtml strips script URLs, entity-encoded or not" {
  let (tree, reports) = run_html(
    "<a href=\"javascript:alert(1)\">one</a><a href=\"java&#9;script:alert(2)\">two</a><a href=\"/ok\">three</a>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><A>one</A><A>two</A><A href=/ok>three</A></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped href on <DIV>: URL scheme is not one a view may navigate to (javascript:alert(1))
      #|dropped href on <DIV>: URL scheme is not one a view may navigate to (java	script:alert(2))
    ),
  )
}

///|
/// Event handlers go by name and by the `on` prefix, so a handler the platform
/// adds tomorrow is already refused.
test "setinnerhtml strips event handlers" {
  let (tree, reports) = run_html(
    "<b onclick=\"steal()\" onfuturething=\"x\">hi</b>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><B>hi</B></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped onclick on <DIV>: attribute is not allowed on <b> here (steal())
      #|dropped onfuturething on <DIV>: attribute is not allowed on <b> here (x)
    ),
  )
}

///|
/// The `<style>` ELEMENT goes, and a `style` ATTRIBUTE is now read rather than
/// dropped. This is the one rule the safe directives have that the dangerous
/// one does not.
///
/// It used to be a blunt drop of both names, because the config's vocabulary is
/// names and `url(…)` lives in a value. `anode/sanitize/css` is what changed:
/// the attribute's value is parsed against `CssPolicy::payload()` and RE-EMITTED,
/// so a fetch is refused and a colour is not. The element stays refused, because
/// a stylesheet is selectors and at-rules as well as declarations and only the
/// declaration half is built.
test "setinnerhtml reads a style attribute and still refuses a style element" {
  let (tree, reports) = run_html(
    "<style>body{display:none}</style><b style=\"background:url(//evil.test/p)\">hi</b>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><B>hi</B></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerHtml on <DIV>: element is not allowed here (<style>)
      #|dropped style on <DIV>: CSS value is not one this sanitizer admits (background:url(//evil.test/p))
    ),
  )
}

///|
/// What a payload MAY now carry, which before this was nothing at all.
///
/// The three answers a payload gets: paint and layout survive, a fetch does
/// not, and leaving the box does not. Each is a different mechanism —
/// `CssPolicy::payload()` is level `Computed` with `overlay` off and
/// `UrlRule::FragmentOnly` — and each is pinned here because the point of the
/// package is that they are three questions rather than one.
test "a payload may paint and lay out, and may not fetch or overlay" {
  let (tree, reports) = run_html(
    "<b style=\"color:#1da1f2;display:flex;gap:4px\">hi</b>",
  )
  inspect(attr_of(tree, "style"), content="color:#1da1f2;display:flex;gap:4px")
  inspect(reports.join("\n"), content="")
  // Overlay: refused, and the rest of the declaration list survives.
  let (over, _) = run_html(
    "<b style=\"position:fixed;inset:0;opacity:0;color:red\">hi</b>",
  )
  inspect(attr_of(over, "style"), content="opacity:0;color:red")
  // A fragment reference to the payload's own gradient: kept, because it
  // fetches nothing.
  let (frag, _) = run_html("<b style=\"fill:url(#grad)\">hi</b>")
  inspect(
    attr_of(frag, "style"),
    content=(
      #|fill:url("#grad")
    ),
  )
  // And the canonical form is generated, not copied: the case folds and the
  // spacing is ours.
  let (canon, _) = run_html("<b style=\"COLOR:  #FFF\">hi</b>")
  inspect(attr_of(canon, "style"), content="color:#fff")
}

///|
/// Template-content insertion mode, the same one a view is parsed in, so a bare
/// `<tr>` survives instead of being dropped or foster-parented into oblivion.
/// This is `parse_fragment`'s doing and is inherited rather than added.
test "setinnerhtml parses in template context" {
  let (tree, _) = run_html("<tr><td>x</td></tr>")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><TR><TD>x</TD></TR></DIV>
    ),
  )
}

///|
/// A host config narrows further, exactly as it does for every other node in
/// the tree. This is the answer to "how do I allow less" — there is no
/// permission to withhold, because there is no unchecked path to permit.
test "setinnerhtml honours a narrowing config" {
  let s = @sanitize.Sanitizer::new({
    ..@sanitize.SanitizerConfig::empty(),
    remove_elements: Some([@sanitize.html("img")]),
  })
  let (tree, reports) = run_html(
    "<p>text <img src=\"/a.png\"></p>",
    sanitizer=s,
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><P>text </P></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerHtml on <DIV>: element is not allowed here (<img>)
    ),
  )
}

// ---------------------------------------------------------------------------
// @setinnersvg

///|
/// The point of the second directive. A bare fragment with no `<svg>` root is
/// SVG here and would be a pile of unknown HTML elements under `@setinnerhtml`
/// — and the difference is not cosmetic, because the sanitizer's element
/// identity is namespace-qualified and would be asking a different question.
///
/// Source case is adjusted by the parser's HTML5 table on the way in, so
/// `lineargradient` as typed arrives as `linearGradient`.
test "setinnersvg gives a bare fragment the SVG namespace" {
  let (tree, reports) = run_svg(
    "<lineargradient></lineargradient><circle r=\"1\"/>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:linearGradient></svg:linearGradient><svg:circle r=1></svg:circle></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// The same fragment through the HTML directive, for contrast. Nothing is
/// refused — these are not dangerous names — but nothing is SVG either, which
/// is why the pair of directives exists rather than one.
test "the same fragment through setinnerhtml is not SVG" {
  let (tree, reports) = run_html(
    "<lineargradient></lineargradient><circle r=\"1\"/>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><LINEARGRADIENT></LINEARGRADIENT><CIRCLE r=1></CIRCLE></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// `svg:script` is a SEPARATE baseline entry from `html:script`, because
/// element identity here is namespace-qualified. Getting this wrong is not
/// hypothetical — it is the bug `docs/sanitizer.md` records finding, where
/// `<svg><script>` passed `check_view` with no violation at all.
test "setinnersvg refuses svg script and svg use" {
  let (tree, reports) = run_svg(
    "<script>alert(1)</script><use href=\"#x\"/><circle/>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:circle></svg:circle></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<script>)
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<use>)
    ),
  )
}

///|
/// SMIL, and the reason it is in the baseline at all: `<animate>` assigns the
/// attribute named by `attributeName` in the browser, AFTER this filter has
/// read the tree and after `Baseline` has read what it built. The `href` the
/// URL rule checked is not the `href` that would navigate. There is no value
/// here to inspect and no later point to inspect it at, which leaves refusing
/// the element.
///
/// Lowercase in source, `animateTransform` in the tree — the parser's HTML5
/// adjustment table — so the baseline entry matches the adjusted spelling.
test "setinnersvg refuses SMIL, which writes attributes after every filter" {
  let (tree, reports) = run_svg(
    "<a href=\"/ok\"><animate attributeName=\"href\" to=\"javascript:alert(1)\"/><animatetransform/><set/><text>x</text></a>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:a href=/ok><svg:text>x</svg:text></svg:a></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<animate>)
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<animateTransform>)
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<set>)
    ),
  )
}

///|
/// `xlink:href` is in `url_attrs` and is navigational, so the SVG spelling of a
/// script URL is refused like the HTML one.
test "setinnersvg strips script URLs in both href spellings" {
  let (tree, reports) = run_svg(
    "<a href=\"javascript:alert(1)\"><text>one</text></a><a xlink:href=\"javascript:alert(2)\"><text>two</text></a>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:a><svg:text>one</svg:text></svg:a><svg:a><svg:text>two</svg:text></svg:a></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped href on <DIV>: URL scheme is not one a view may navigate to (javascript:alert(1))
      #|dropped xlink:href on <DIV>: URL scheme is not one a view may navigate to (javascript:alert(2))
    ),
  )
}

///|
/// `<foreignObject>` is the one legitimate route back to HTML, and it is
/// handled by the parser labelling its contents HTML rather than by anything
/// here — which means the sanitizer judges them as HTML, with `html:script` on
/// the baseline. The escape hatch and the rule that covers it are the same
/// mechanism.
test "setinnersvg admits foreignObject and judges its content as HTML" {
  let (tree, reports) = run_svg(
    "<foreignobject><p>text</p><script>alert(1)</script></foreignobject>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:foreignObject><P>text</P></svg:foreignObject></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<script>)
    ),
  )
}

///|
/// A payload that closes the wrapper early is TRUNCATED, not escaped. The
/// documented divergence in `@anode.parse_fragment_svg`, pinned here because
/// the safe direction to fail in is a thing a future parser change could
/// silently reverse: the alternative is `<img>` in the HTML namespace, which is
/// content that left the namespace it was promised.
test "setinnersvg truncates a payload that closes the wrapper" {
  let (tree, reports) = run_svg("<circle/></svg><img src=\"/a.png\">")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:circle></svg:circle></DIV>
    ),
  )
  debug_inspect(reports, content="[]")
}

///|
/// The same in SVG, where `<svg><style>` is a stylesheet like any other — which
/// is why the element is refused in both namespaces rather than just in HTML.
test "setinnersvg reads a style attribute and still refuses an svg style element" {
  let (tree, reports) = run_svg(
    "<style>circle{r:100}</style><circle style=\"fill:url(//evil.test/p)\"/>",
  )
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:circle></svg:circle></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped setInnerSvg on <DIV>: element is not allowed here (<style>)
      #|dropped style on <DIV>: CSS value is not one this sanitizer admits (fill:url(//evil.test/p))
    ),
  )
}

///|
/// SVG PRESENTATION ATTRIBUTES, which is the case this whole package widens.
///
/// `fill` and `stroke` are not ordinary attributes: they set the CSS property
/// of the same name, with the same grammar, so `fill="url(…)"` is a fetch and
/// `fill="red"` is a colour. Before there was a value rule the only way to tell
/// them apart was not to try — `dyncomp/policy/view_authority.mbt` refuses both
/// by NAME for an untrusted guest, on the grounds that a dynamic value could
/// have been either.
///
/// Under `CssPolicy::payload()` the question is asked of the value instead: a
/// colour survives, a fragment reference to the payload's own gradient survives
/// because it fetches nothing, and an external URL does not.
test "an svg presentation attribute is judged by its value" {
  let (paint, reports) = run_svg(
    "<circle fill=\"#1da1f2\" stroke=\"currentcolor\" stroke-width=\"2\"/>",
  )
  inspect(
    ns_shape(paint),
    content=(
      #|<DIV><svg:circle fill=#1da1f2 stroke-width=2 stroke=currentcolor></svg:circle></DIV>
    ),
  )
  inspect(reports.join("\n"), content="")
  let (frag, _) = run_svg("<circle fill=\"url(#grad)\"/>")
  inspect(
    attr_of(frag, "fill"),
    content=(
      #|url("#grad")
    ),
  )
  let (fetch, dropped) = run_svg("<circle fill=\"url(//evil.test/p)\"/>")
  inspect(attr_of(fetch, "fill"), content="-")
  inspect(
    dropped.join("\n"),
    content=(
      #|dropped fill on <DIV>: CSS value is not one this sanitizer admits (url(//evil.test/p))
    ),
  )
}

///|
/// Handlers on a namespaced element are the case that no accident of routing
/// covers: `set_prop`'s property path excludes namespaced elements, so an
/// `onclick` here would be written verbatim as a live content attribute and SVG
/// honours it. The prefix rule is the only thing standing there.
test "setinnersvg strips event handlers, which SVG would otherwise honour" {
  let (tree, reports) = run_svg("<circle onclick=\"steal()\"/>")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV><svg:circle></svg:circle></DIV>
    ),
  )
  inspect(
    reports.join("\n"),
    content=(
      #|dropped onclick on <DIV>: attribute is not allowed on <circle> here (steal())
    ),
  )
}

// ---------------------------------------------------------------------------
// Both, and neither

///|
/// A value of the wrong shape under one of the names is dropped rather than
/// reasoned about, so `set_prop`'s fail-closed branch does not clear an element
/// over an authoring mistake. Same rule `MdFilter` follows.
test "a wrongly-shaped value drops the attribute and leaves the element" {
  let tree = @vdom.h(
    "DIV",
    attrs=Map::from_array([(SAFE_HTML_ATTR, Str("<b>not a SafeHtml</b>"))]),
    childs=[Text("declared")],
  )
  SafeMarkupFilter::new().filter_tree(tree)
  guard tree is Node(el) else { fail("expected an element") }
  debug_inspect(el.attrs.contains(SAFE_HTML_ATTR), content="false")
  inspect(
    ns_shape(tree),
    content=(
      #|<DIV>declared</DIV>
    ),
  )
}

///|
/// An element carrying neither name is untouched, including its attributes —
/// this filter has no opinion about anything but its own two directives, and
/// the URL and handler rules that DO apply everywhere are `Baseline`'s job,
/// which runs after it.
test "an element with neither directive is left alone" {
  let tree = @vdom.h("A", attrs={
    "href": Str("javascript:alert(1)"),
    "style": Str("color:red"),
  })
  let f = SafeMarkupFilter::new()
  f.filter_tree(tree)
  inspect(
    ns_shape(tree),
    content=(
      #|<A style=color:red href=javascript:alert(1)></A>
    ),
  )
  debug_inspect(f.take_reports(), content="[]")
}
