// @loop-with tests (JS renderer.js loop pipeline): keys authority, slice
// ranges, iterData threading, and render/rebuild mirroring.

///|
test "@loop-with keys are authoritative and skip @when" {
  let state = state_of([
    ("items", List([Str("a"), Str("b"), Str("c")])),
    ("plan", Fn(_args => Map({ "keys": List([Num(2), Num(0)]) }))),
    ("never", Fn(_args => Bool(false))), // would filter everything out
  ])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\" @when=\"never\" @loop-with=\"plan\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":2}§--><li>c</li><!--§{"$":"Each","nid":1,"si":0}§--><li>a</li></ul>
    ),
  )
}

///|
test "@loop-with start/end slice the iteration (JS slice semantics)" {
  let state = state_of([
    ("items", List([Num(10), Num(20), Num(30), Num(40)])),
    ("page", Fn(_args => Map({ "start": Num(1), "end": Num(3) }))),
  ])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\" @loop-with=\"page\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":1}§--><li>20</li><!--§{"$":"Each","nid":1,"si":2}§--><li>30</li></ul>
    ),
  )
}

///|
test "@loop-with negative start counts from the end" {
  let state = state_of([
    ("items", List([Num(10), Num(20), Num(30), Num(40)])),
    ("tail", Fn(_args => Map({ "start": Num(-2) }))),
  ])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\" @loop-with=\"tail\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":2}§--><li>30</li><!--§{"$":"Each","nid":1,"si":3}§--><li>40</li></ul>
    ),
  )
}

///|
test "@loop-with iterData flows into @when" {
  let state = state_of([
    ("items", List([Num(1), Num(2), Num(3)])),
    ("data", Fn(_args => Map({ "iterData": Map({ "min": Num(2) }) }))),
    (
      "big",
      Fn(args => {
        match args {
          // (this, key, value, iterData)
          [_, _, Num(v), Map(idata)] =>
            match idata.get("min") {
              Some(Num(min)) => Bool(v >= min)
              _ => Bool(false)
            }
          _ => Bool(false)
        }
      }),
    ),
  ])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\" @when=\"big\" @loop-with=\"data\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":1}§--><li>2</li><!--§{"$":"Each","nid":1,"si":2}§--><li>3</li></ul>
    ),
  )
}

///|
test "@loop-with iterData reaches @enrich-with at render AND rebuild" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<ul><li @each=\".items\" @loop-with=\"plan\" @enrich-with=\"deco\"><button @on.click=\"go\"><x text=\"@label\"></x></button></li></ul>",
  )
  let state : @tutuca.Value = Map({
    "items": List([Str("x")]),
    "plan": Fn(_args => Map({ "iterData": Map({ "tag": Str("!") }) })),
    "deco": Fn(args => {
      match args {
        // (this, binds, key, value, iterData)
        [_, Map(binds), _, Str(v), Map(idata)] => {
          let tag = match idata.get("tag") {
            Some(Str(t)) => t
            _ => "?"
          }
          binds["label"] = Str(v + tag)
          Null
        }
        _ => Null
      }
    }),
  })
  let container = mount(reg, state)
  // rendered with the enriched bind
  assert_true(container.to_html().contains("x!"))
  // and the REBUILT stack replays the same iterData through each_binds
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  let st = rebuilt(reg, state, container, btn)
  assert_true(@tutuca.Stack::lookup_bind(st, "label") is Str("x!"))
}

///|
test "clean_vdom strips metas and internal stamps, keeps user content" {
  let reg = @render.ViewRegistry::new()
  reg.add(
    "main", "<div data-test=\"keep\"><!-- note --><ul><li @each=\".items\"><x text=\"@value\"></x></li></ul><button @on.click=\"go\">x</button></div>",
  )
  let state : @tutuca.Value = Map({ "items": List([Str("a"), Str("b")]) })
  let stack = @render.RenderStack::new(state)
  let ctx = @render.RenderCtx::new(view_resolver=reg)
  guard @render.render_root(state, stack, ctx) is Some(v) else {
    fail("did not render")
  }
  guard @render.clean_vdom(v) is Some(clean) else { fail("cleaned to None") }
  let doc = @memdom.document()
  let html = @vdom.to_dom(clean, @vdom.RenderOpts::new(doc)).to_html()
  assert_eq(
    html, "<div data-test=\"keep\"><!-- note --><ul><li>a</li><li>b</li></ul><button>x</button></div>",
  )
}
