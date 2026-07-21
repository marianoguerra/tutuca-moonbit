// Port of the macro suites from tutuca test/anode.test.js: expansion,
// nesting, slots, recursion rejection, and macro-attr source strings.

///|
priv struct TestScope {
  macros : Map[String, @anode.Macro]
}

///|
impl @anode.MacroScope for TestScope with fn lookup_macro(self, name) {
  self.macros.get(name)
}

///|
fn mk_macro(defaults : Map[String, String], raw_view : String) -> @anode.Macro {
  { defaults, raw_view }
}

///|
fn compile_view(
  raw_view : String,
  macros : Map[String, @anode.Macro],
) -> (@anode.View, @anode.ParseContext) raise @anode.MacroError {
  let v = @anode.View::new("main", raw_view~)
  let px = @anode.ParseContext::new()
  v.compile(px, TestScope::{ macros, }, cid=LNum(0))
  (v, px)
}

///|
test "expand simple macro" {
  let m = mk_macro(
    { "value": ".text", "oninput": "$setText" },
    "<input :value=\"^value\" @on.input=\"^oninput value\" />",
  )
  let px = @anode.ParseContext::new()
  let n = m.expand(
    px.enter_macro("m", { "value": ".text", "oninput": "$setText" }, Map([])),
  )
  guard n is Dom(d)
  guard d.attrs is DynAttrs(items)
  assert_true(items[0] is Plain(name="value", val=Field("text")))
  assert_eq(px.events.length(), 1)
  assert_true(px.events[0].handlers[0].handler.handler is Method("setText"))
  // Same macro expanded with other vars picks them up.
  let px2 = @anode.ParseContext::new()
  let n2 = m.expand(
    px2.enter_macro("m", { "value": ".foo", "oninput": "$setFoo" }, Map([])),
  )
  guard n2 is Dom(d2)
  guard d2.attrs is DynAttrs(items2)
  assert_true(items2[0] is Plain(name="value", val=Field("foo")))
  assert_true(px2.events[0].handlers[0].handler.handler is Method("setFoo"))
}

///|
test "expand nested macro" {
  let input_macro = mk_macro(
    { "value": ".text", "oninput": "$setText" },
    "<input :value=\"^value\" @on.input=\"^oninput value\" />",
  )
  let outer_macro = mk_macro(
    { "value": ".title" },
    "<div :title=\"^value\"><x:input :value=\".foo\" :oninput=\"$setFoo\"></x:input><p :title=\"^value\"></p></div>",
  )
  let (_, px) = compile_view("<div><x:outer :value=\".bar\"></x:outer></div>", {
    "input": input_macro,
    "outer": outer_macro,
  })
  guard px.macro_nodes[0] is MacroCall(m)
  guard m.node is Some(Dom(outer_div))
  guard outer_div.attrs is DynAttrs(outer_attrs)
  assert_true(outer_attrs[0] is Plain(name="title", val=Field("bar")))
  guard outer_div.childs[1] is Dom(p)
  guard p.attrs is DynAttrs(p_attrs)
  assert_true(p_attrs[0] is Plain(name="title", val=Field("bar")))
  guard outer_div.childs[0] is MacroCall(inner)
  guard inner.node is Some(Dom(input_el))
  guard input_el.attrs is DynAttrs(input_attrs)
  assert_true(input_attrs[0] is Plain(name="value", val=Field("foo")))
  assert_true(px.events[0].handlers[0].handler.handler is Method("setFoo"))
}

///|
test "reject directly recursive macro" {
  let self_macro = mk_macro(Map([]), "<div><x:self></x:self></div>")
  try
    compile_view("<div><x:self></x:self></div>", { "self": self_macro })
    |> ignore
  catch {
    RecursiveMacro(name) => assert_eq(name, "self")
  } noraise {
    _ => fail("expected recursive macro expansion to raise")
  }
}

///|
test "multiple instances at the same level are fine" {
  let card = mk_macro(Map([]), "<div class=\"card\"></div>")
  let (_, px) = compile_view("<div><x:card></x:card><x:card></x:card></div>", {
    "card": card,
  })
  assert_eq(px.macro_nodes.length(), 2)
}

///|
test "multiple instances across different macros are fine" {
  let a = mk_macro(Map([]), "<div class=\"a\"><x:c></x:c></div>")
  let b = mk_macro(Map([]), "<div class=\"b\"><x:a></x:a><x:c></x:c></div>")
  let c = mk_macro(Map([]), "<div class=\"c\"></div>")
  let (_, px) = compile_view("<div><x:a></x:a><x:b></x:b><x:c></x:c></div>", {
    "a": a,
    "b": b,
    "c": c,
  })
  assert_true(px.macro_nodes.length() >= 3)
}

///|
test "reject recursive macro through a chain" {
  let a = mk_macro(Map([]), "<div class=\"a\"><x:b></x:b></div>")
  let b = mk_macro(Map([]), "<div class=\"b\"><x:c></x:c></div>")
  let c = mk_macro(Map([]), "<div class=\"c\"><x:a></x:a></div>")
  try
    compile_view("<div><x:a></x:a></div>", { "a": a, "b": b, "c": c }) |> ignore
  catch {
    RecursiveMacro(name) => assert_eq(name, "a")
  } noraise {
    _ => fail("expected chained recursion to raise")
  }
}

///|
test "reject indirectly recursive macro" {
  let a = mk_macro(Map([]), "<div><x:b></x:b></div>")
  let b = mk_macro(Map([]), "<div><x:a></x:a></div>")
  try
    compile_view("<div><x:a></x:a></div>", { "a": a, "b": b }) |> ignore
  catch {
    RecursiveMacro(name) => assert_eq(name, "a")
  } noraise {
    _ => fail("expected indirect recursion to raise")
  }
}

///|
test "unknown macro compiles to a bad-macro comment" {
  let (_, px) = compile_view("<div><x:nope></x:nope></div>", Map([]))
  guard px.macro_nodes[0] is MacroCall(m)
  guard m.node is Some(Comment(c))
  assert_eq(c.val, "bad macro: nope")
}

///|
test "parse macro slots" {
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse(
      "<x:m>\n  <span @text=\"'hi'\"></span>\n  <x slot=\"a\">\n    <p>hello</p>\n    <em>bye</em>\n  </x>\n  <x slot=\"b\"><footer>Footer</footer></x>\n</x:m>",
      px,
    )
    is Some(MacroCall(m))
  assert_true(m.slots.get("a") is Some(Fragment(_)))
  assert_true(m.slots.get("b") is Some(Dom(_)))
}

///|
test "expand macro slot: default and override" {
  let post = mk_macro(
    Map([]),
    "<article><x:slot name=\"title\"><h1>My Post</h1></x:slot></article>",
  )
  // Default content
  let (_, px) = compile_view("<div><x:post></x:post></div>", { "post": post })
  guard px.macro_nodes[0] is MacroCall(m)
  assert_eq(m.name, "post")
  guard m.node is Some(Dom(article))
  guard article.childs[0] is Dom(h1)
  assert_eq(h1.tag, "h1")
  guard h1.childs[0] is Text(t)
  assert_eq(t.val, "My Post")
  // Slot override
  let (_, px2) = compile_view(
    "<div><x:post><x slot=\"title\"><h2>Hello</h2></x></x:post></div>",
    { "post": post },
  )
  guard px2.macro_nodes[0] is MacroCall(m2)
  guard m2.node is Some(Dom(article2))
  guard article2.childs[0] is Dom(h2)
  assert_eq(h2.tag, "h2")
  guard h2.childs[0] is Text(t2)
  assert_eq(t2.val, "Hello")
}

///|
test "parse mixed macro attrs round-trip to source strings" {
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse(
      "<x:m class=\"foo\" :name=\"foo\" :type=\"Foo\" :bool=\"false\" :num=\"42\" :str=\"'hi'\" :field=\".bar\" :bind=\"@key\" :seq=\".a[.b]\" :dyn=\"*dynamic\"></x:m>",
      px,
    )
    is Some(MacroCall(m))
  @debug.assert_eq(m.attrs, {
    "class": "'foo'",
    "name": "foo",
    "type": "Foo",
    "bool": "false",
    "num": "42",
    "str": "'hi'",
    "field": ".bar",
    "bind": "@key",
    "seq": ".a[.b]",
    "dyn": "*dynamic",
  })
}

///|
test "wrapper macro attrs wrap the macro call" {
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse(
      "<x:m class=\"foo\" :name=\"foo\" @show=\".loading\"></x:m>", px,
    )
    is Some(Show(w))
  assert_true(w.val is Field("loading"))
  guard w.node is MacroCall(m)
  @debug.assert_eq(m.attrs, { "class": "'foo'", "name": "foo" })
}
