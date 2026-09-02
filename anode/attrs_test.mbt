// Attribute-directive suites
// (parse-side assertions): wrapper registration and ordering, @enrich-with
// scope vs each attachment, @if/@then/@else, and events.

///|
fn aparse(html : String) -> (@anode.ANode, @anode.ParseContext) {
  let px = @anode.ParseContext::new()
  (@anode.ANode::parse(html, px).unwrap(), px)
}

///|
test "@show/@hide wrappers are unregistered" {
  let (root, px) = aparse("<div @show=\".isOpen\">hi</div>")
  guard! root is Show(w)
  assert_true(w.node_id is None)
  assert_eq(px.nodes.length(), 0)
  let (root2, px2) = aparse("<div @hide=\".isOpen\">hi</div>")
  guard! root2 is Hide(w2)
  assert_true(w2.node_id is None)
  assert_eq(px2.nodes.length(), 0)
}

///|
test "@enrich-with without @each wraps in a registered Scope" {
  let (root, px) = aparse("<div @enrich-with=\"$x\">hi</div>")
  guard! root is Scope(s)
  @debug.assert_eq(s.node_id, Some(0))
  assert_true(s.val is EMethod(name="x", ..))
  assert_eq(px.nodes.length(), 1)
  // Bare handler-name form resolves through the alter namespace.
  let (root2, _) = aparse("<div @enrich-with=\"enrich\">hi</div>")
  guard! root2 is Scope(s2)
  assert_true(s2.val is EHandlerName(name="enrich", ns=Alter, ..))
}

///|
test "@each with @when/@enrich-with/@loop-with fills iter_info" {
  let (root, px) = aparse(
    "<li @each=\".items\" @when=\"$w\" @enrich-with=\"$e\" @loop-with=\"$l\">x</li>",
  )
  guard! root is Each(e)
  assert_true(e.iter_info.when_val is Some(EMethod(name="w", ..)))
  assert_true(e.iter_info.enrich_with_val is Some(EMethod(name="e", ..)))
  assert_true(e.iter_info.loop_with_val is Some(EMethod(name="l", ..)))
  assert_true(!e.from_render_each)
  assert_eq(px.nodes.length(), 1)
}

///|
test "wrap order: first directive is outermost" {
  let (root, px) = aparse(
    "<div @show=\".s\" @hide=\".h\" @enrich-with=\"$e\" @each=\".xs\">x</div>",
  )
  guard! root is Show(s)
  guard! s.node is Hide(h)
  guard! h.node is Scope(sc)
  guard! sc.node is Each(e)
  assert_true(e.node is Dom(_))
  // Scope and Each register (in wrap order: innermost first).
  assert_eq(px.nodes.length(), 2)
  assert_true(px.nodes[0] is Each(_))
  assert_true(px.nodes[1] is Scope(_))
}

///|
test "scope stamps data-nid on the wrapped node" {
  let (root, _) = aparse("<div @enrich-with=\"$x\">hi</div>")
  guard! root is Scope(s)
  guard! s.node is Dom(d)
  guard! d.attrs is ConstAttrs(m)
  assert_true(m.get("data-nid") is Some(LNum(0)))
}

///|
test "@if.attr with @then/@else evaluates per render" {
  let (root, _) = aparse(
    "<div @if.class=\".cond\" @then=\"'a'\" @else=\"'d'\"></div>",
  )
  guard! root is Dom(d)
  guard! d.attrs is DynAttrs(items)
  guard! items[0] is If(ia)
  assert_eq(ia.name, "class")
  assert_true(
    ia.cond_val is ERead(place={ root: PState("cond"), steps: [], .. }, ..),
  )
  assert_true(ia.then_val is Some(ELit(lit=LStr("a"), ..)))
  assert_true(ia.else_val is Some(ELit(lit=LStr("d"), ..)))
}

///|
test "@if with only @then leaves else unset" {
  let (root, _) = aparse("<div @if.class=\".cond\" @then=\"'a'\"></div>")
  guard! root is Dom(d)
  guard! d.attrs is DynAttrs(items)
  guard! items[0] is If(ia)
  assert_true(ia.then_val is Some(_))
  assert_true(ia.else_val is None)
}

///|
test "events register data-eid and handler args" {
  let (root, px) = aparse(
    // No `MyType`: a component type is not a value, so a handler argument
    // cannot be one. A handler that needs a type asks for it by name.
    "<button @on.click=\"myHandler @v .f true 42 12.5 e.value\">go</button>",
  )
  guard! root is Dom(d)
  guard! d.attrs is ConstAttrs(m)
  assert_true(m.get("data-eid") is Some(LNum(0)))
  assert_eq(px.events.length(), 1)
  let ev = px.events[0]
  assert_eq(ev.id, 0)
  assert_eq(ev.handlers.length(), 1)
  let h = ev.handlers[0]
  assert_eq(h.name, "click")
  assert_true(
    h.handler.handler is EHandlerName(name="myHandler", ns=Receive, ..),
  )
  assert_eq(h.handler.args.length(), 6)
  assert_true(
    h.handler.args[0] is ERead(place={ root: PBind("v"), steps: [], .. }, ..),
  )
  assert_true(
    h.handler.args[1] is ERead(place={ root: PState("f"), steps: [], .. }, ..),
  )
  assert_true(h.handler.args[2] is ELit(lit=LBool(true), ..))
  assert_true(h.handler.args[3] is ELit(lit=LNum(42), ..))
  assert_true(h.handler.args[4] is ELit(lit=LNum(12.5), ..))
  assert_true(h.handler.args[5] is EEventPath(segments=["value"], ..))
}

///|
test "two events on one node share the same eid" {
  let (root, px) = aparse(
    "<input @on.input=\"h1 e.value\" @on.keydown+send=\"h2\" />",
  )
  guard! root is Dom(d)
  guard! d.attrs is ConstAttrs(m)
  assert_true(m.get("data-eid") is Some(LNum(0)))
  assert_eq(px.events.length(), 1)
  let ev = px.events[0]
  assert_eq(ev.handlers.length(), 2)
  assert_eq(ev.handlers[0].name, "input")
  assert_eq(ev.handlers[1].name, "keydown")
  @debug.assert_eq(ev.handlers[1].modifiers, ["send"])
}

///|
test "@bind parses to a mirrored property and a pending setter event" {
  let (root, px) = aparse("<input type=\"checkbox\" @bind=\".done\" />")
  guard! root is Dom(d)
  guard! d.bind is Some(bind)
  assert_true(
    bind.target is ERead(place={ root: PState("done"), steps: [], .. }, ..),
  )
  assert_eq(bind.property, "checked")
  guard! d.attrs is DynAttrs(items)
  assert_true(
    items.any(item => {
      item
      is Plain(
        name="checked",
        val=ERead(place={ root: PState("done"), steps: [], .. }, ..)
      )
    }),
  )
  assert_eq(px.events.length(), 1)
  assert_eq(px.events[0].handlers.length(), 1)
  let h = px.events[0].handlers[0]
  assert_eq(h.name, "input")
  assert_true(h.handler.handler is ELit(lit=LNull, ..))
  assert_true(
    h.handler.action
    is Some(PropertySet(name="done", value=EEventPath(segments=["value"], ..))),
  )
  assert_true(h.handler.args.is_empty())
  assert_true(h.binding is Some(BindPending))
}

///|
test "unknown directive reports an issue but keeps the element" {
  let issues : Array[@anode.ParseIssue] = []
  let (root, _) = collecting_parse("<div @nope=\"v\">x</div>", issues)
  assert_true(root is Some(Dom(_)))
  assert_eq(issues.length(), 1)
  assert_true(issues[0] is UnknownDirective(name="nope", value="v"))
}

///|
/// A branch that was written and did not parse is reported, where an unwritten
/// one is not: `@then="btn btn-primary"` is a class list that forgot its
/// quotes, and a silent render as an element with no class at all is the
/// mistake a static `class` beside the `@if.class` hides best.
test "an @if branch that does not parse says so" {
  let issues : Array[@anode.ParseIssue] = []
  let (root, _) = collecting_parse(
    "<div @if.class=\".on\" @then=\"btn btn-primary\" @else=\"'btn'\"></div>", issues,
  )
  guard! root is Some(Dom(d))
  guard! d.attrs is DynAttrs(items)
  guard! items[0] is If(ia)
  assert_true(ia.then_val is None)
  assert_true(ia.else_val is Some(_))
  assert_eq(issues.length(), 1)
  assert_true(
    issues[0] is BadValue(role=Directive(name="then"), value="btn btn-primary"),
  )
}

///|
priv struct IssueCollector {
  issues : Array[@anode.ParseIssue]
}

///|
impl @anode.ParseHandler for IssueCollector with fn on_parse_issue(
  self,
  issue,
  _tag,
) {
  self.issues.push(issue)
}

///|
fn collecting_parse(
  html : String,
  issues : Array[@anode.ParseIssue],
) -> (@anode.ANode?, @anode.ParseContext) {
  let px = @anode.ParseContext::new(handler=IssueCollector::{ issues, })
  (@anode.ANode::parse(html, px), px)
}
