// The load-bearing test for ahead-of-time view compilation: a component
// built from the GENERATED TREE must render byte-identically to the same
// component built by parsing the same view source at startup.
//
// It lives in cli/ because this is the one package that already imports both
// ends — @viewgen (which produces the tree) and @render/@memdom/@component
// (which consume it). The generated module normally reaches the runtime as
// MoonBit source; here the same values are built directly from @viewgen's
// parse, which exercises every seam except the emitter's text formatting
// (the emitter is snapshot-tested in viewgen/emit_test.mbt).

///|
priv struct IrState {
  label : String
  count : Int
  history : Array[Int]
} derive(ToJson, FromJson)

///|
fn ir_state() -> IrState {
  { label: "Counter", count: 2, history: [1, 2] }
}

///|
/// Render one component's main view to HTML through the real render path.
fn render_comp(comp : @component.Component) -> String raise {
  let scope = @component.ComponentStack::new()
  scope.register_components([comp])
  scope.compile_all()
  let inst = comp.make(Map([]))
  let stack = @render.RenderStack::new(inst, comps=scope.comps)
  let ctx = @render.RenderCtx::new(view_resolver=scope.comps)
  match @render.render_root(inst, stack, ctx) {
    Some(v) =>
      match @render.clean_vdom(v) {
        Some(clean) => {
          let doc = @memdom.document()
          @vdom.to_dom(clean, @vdom.RenderOpts::new(doc)).to_html()
        }
        None => "<!-- nothing -->"
      }
    None => "<!-- nothing -->"
  }
}

///|
/// Views exercising the parts of the tree the emitter has to reproduce:
/// constant and dynamic attributes, text slots, an @each loop, conditional
/// wrappers, an @if attribute, event handlers with several argument kinds,
/// and a nested SVG namespace.
let ir_html : String =
  #|<template>
  #|  <div class="counter" :title=".label">
  #|    <h1><x text=".label"></x>: <span id="count"><x text=".count"></x></span></h1>
  #|    <p @show=".count"><x text="'shown'"></x></p>
  #|    <p @hide=".count">hidden</p>
  #|    <button id="inc" @on.click="add 1" @on.keydown+send="add -2.5">+1</button>
  #|    <input id="label" :value=".label" @on.input="setLabel value">
  #|    <b @if.class=".count" @then.class="on" @else.class="off">flag</b>
  #|    <ul id="history"><li @each=".history"><x text="@value"></x></li></ul>
  #|    <svg viewBox="0 0 1 1"><circle r="1"></circle></svg>
  #|  </div>
  #|</template>

///|
test "a component built from the compiled tree renders identically" {
  let views = @viewgen.split_views(ir_html)
  assert_true(@viewgen.ir_supported(views.views))
  let from_source = @component.component(
    name="IrFromSource",
    view=views.views[0].source,
    style=views.views[0].style,
    init=ir_state(),
  )
  let from_tree = @component.component(
    name="IrFromTree",
    compiled_views=@viewgen.compiled_views(views),
    init=ir_state(),
  )
  let want = render_comp(from_source)
  let got = render_comp(from_tree)
  // Component ids differ between the two, and data-cid is stamped per
  // component, so compare with that one attribute normalized away.
  assert_eq(strip_cid(got), strip_cid(want))
  // Not vacuous: the view really did render.
  assert_true(want.contains("<span id=\"count\">2</span>"))
  assert_true(want.contains("<li>1</li><li>2</li>"))
}

///|
test "handlers dispatch through a compiled tree" {
  let views = @viewgen.split_views(ir_html)
  let comp = @component.component(
    name="IrDispatch",
    compiled_views=@viewgen.compiled_views(views),
    init=ir_state(),
    update=(s : IrState, msg, _ctx) => {
      match msg {
        Input("add", [Num(d)]) => Some({ ..s, count: s.count + d.to_int() })
        _ => None
      }
    },
  )
  let scope = @component.ComponentStack::new()
  scope.register_components([comp])
  scope.compile_all()
  // The event table survived the round trip: the renderer finds the handler
  // for the element's data-eid, which is what a real DOM click resolves.
  guard comp.get_view(None) is Some(view)
  guard view.ctx is Some(px)
  let names : Array[String] = []
  for ev in px.events {
    for h in ev.handlers {
      names.push(h.name + ":" + h.handler.handler.to_string())
    }
  }
  assert_eq(names, ["click:add", "keydown:add", "input:setLabel"])
  // …and the nodes array is addressable by the node_ids the tree carries.
  assert_true(px.nodes.length() > 0)
  for i, n in px.nodes {
    assert_true(node_id_of(n) is Some(id) && id == i)
  }
}

///|
/// The node_id a registered node carries, for the index check above.
fn node_id_of(n : @anode.ANode) -> Int? {
  match n {
    RenderText(d) => d.node_id
    Render(d) => Some(d.node_id)
    RenderIt(d) => Some(d.node_id)
    Show(d) | Hide(d) | PushView(d) | Scope(d) => d.node_id
    Each(d) => Some(d.node_id)
    _ => None
  }
}

///|
/// Drop every `data-cid="N"` so two components' output can be compared.
fn strip_cid(html : String) -> String {
  let out = StringBuilder::new()
  let chars = html.to_array()
  let needle = " data-cid=\"".to_array()
  let mut i = 0
  while i < chars.length() {
    let mut matched = i + needle.length() <= chars.length()
    if matched {
      for k in 0..<needle.length() {
        if chars[i + k] != needle[k] {
          matched = false
          break
        }
      }
    }
    if matched {
      i = i + needle.length()
      while i < chars.length() && chars[i] != '"' {
        i = i + 1
      }
      i = i + 1
    } else {
      out.write_char(chars[i])
      i = i + 1
    }
  }
  out.to_string()
}
