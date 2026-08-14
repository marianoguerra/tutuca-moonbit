// `CssFilter`: the CSS value rule over a tree the filter did not build.

///|
/// Run the filter over one element and report what the attribute became.
fn run_css(
  attrs : Array[(String, @vdom.AttrValue)],
  policy? : @safecss.CssPolicy = @safecss.CssPolicy::payload(),
) -> (String, String) {
  let el = @vdom.h("div", attrs=Map::from_array(attrs))
  let f = @filter.CssFilter::new(policy~)
  f.filter_tree(el)
  let shown = match el {
    Node(e) => {
      let out = e.attrs
        .iter()
        .map(pair => "\{pair.0}=\{pair.1.to_attr_string()}")
        .to_array()
      out.sort()
      out.join(" ")
    }
    _ => "?"
  }
  (shown, f.take_reports().map(@filter.Dropped::to_string).join("\n"))
}

///|
/// The value that reaches the DOM is the one the validator produced, always —
/// including when nothing about it needed changing.
///
/// Rewriting unconditionally is the point. If the filter only replaced values it
/// had altered, "unchanged" would mean "the author's bytes went through
/// untouched", and the design would have to reason about which of the two paths
/// a given value took. It does not.
test "a surviving value is rewritten, not approved" {
  inspect(
    run_css([("style", Str("COLOR : #FFF ; margin:  0px  4px"))]).0,
    content="style=color:#fff;margin:0px 4px",
  )
}

///|
/// The three answers, one per mechanism: the level, the overlay switch and the
/// URL rule.
test "what a payload policy admits on an app's own tree" {
  // Level: paint and layout survive.
  inspect(
    run_css([("style", Str("display:flex;gap:4px"))]).0,
    content="style=display:flex;gap:4px",
  )
  // Overlay: refused, and the rest of the list survives.
  let (kept, reports) = run_css([("style", Str("position:fixed;color:red"))])
  inspect(kept, content="style=color:red")
  inspect(reports, content="")
  // URL: a fragment fetches nothing and survives; an external one does not.
  inspect(
    run_css([("fill", Str("url(#grad)"))]).0,
    content=(
      #|fill=url("#grad")
    ),
  )
  let (gone, dropped) = run_css([("fill", Str("url(\"https://evil.test/p\")"))])
  inspect(gone, content="")
  inspect(
    dropped,
    content="dropped fill on <DIV>: CSS value is not one this policy admits (url(\"https://evil.test/p\"))",
  )
}

///|
/// An app policy screens a `url()` through the rule this package already owns,
/// rather than through a second one.
///
/// `CssPolicy`'s `screen` defaults to REFUSING, so this is also the test that
/// says the callback is actually being passed: without it, every one of these
/// would be dropped.
test "url() goes through the scheme rule already here" {
  let app = @safecss.CssPolicy::app()
  inspect(
    run_css([("style", Str("background-image:url(\"/logo.png\")"))], policy=app).0,
    content=(
      #|style=background-image:url("/logo.png")
    ),
  )
  let (gone, dropped) = run_css(
    [("style", Str("background-image:url(\"javascript:alert(1)\")"))],
    policy=app,
  )
  inspect(gone, content="")
  inspect(dropped.contains("javascript"), content="true")
}

///|
/// A structured value is not a declaration list, for the reason the URL rule
/// gives about `Data`: `set_prop` sends it down the property path, where the
/// IDL setter's ToString reassembles it into a string nothing checked.
test "a structured value is dropped rather than stringified" {
  let (kept, dropped) = run_css([("style", Data(["color:red"]))])
  inspect(kept, content="")
  inspect(dropped.contains("style"), content="true")
}

///|
/// Attributes that are not CSS are not touched, and the no-op path does not
/// allocate to discover that.
test "a name that is not CSS passes through" {
  inspect(
    run_css([("href", Str("/a")), ("class", Str("x")), ("data-eid", Str("3"))]).0,
    content="class=x href=/a data-eid=3",
  )
}
