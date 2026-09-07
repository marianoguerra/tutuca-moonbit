// The load-bearing test for ahead-of-time view compilation: a component built
// from the tree the reader produced must RENDER, dispatch and index the way a
// component does.
//
// It used to be a differential — the same view source parsed at startup and
// compiled ahead of time, compared byte for byte — and that half went with the
// notation. A `.tutu` view has one form: the tree the reader answers. What is
// left is the claim the differential was standing in for, asserted directly.
//
// It lives in cli/ because this is the one package that already imports both
// ends — @viewgen (which produces the tree) and @render/@memdom/@component
// (which consume it). The generated module normally reaches the runtime as
// MoonBit source; here the same values are built directly from @viewgen's
// read, which exercises every seam except the emitter's text formatting
// (the emitter is snapshot-tested in viewgen/emit_test.mbt).

///|
priv struct IrState {
  label : String
  count : Int
  history : Array[Int]
}

///|
fn ir_state() -> IrState {
  { label: "Counter", count: 2, history: [1, 2], }
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
let ir_src : String =
  #|spec:
  #|  Ir:
  #|    field label :: String
  #|    field count :: Int
  #|    field history :: List.of(Int)
  #|
  #|view:
  #|  Ir:
  #|    @div(~class: "counter", ~title: it.label){
  #|      @h1{@(it.label): @span(~id: "count"){@(it.count)}}
  #|      @show(it.count){@p{shown}}
  #|      @hide(it.count){@p{hidden}}
  #|      @button(~id: "inc", ~on_click: add(1), ~on_keydown: add(-2.5) ~send){+1}
  #|      @input(~id: "label", ~value: it.label, ~on_input: setLabel(e.value))
  #|      @b(~class: if it.count | "on" | "off"){flag}
  #|      @ul(~id: "history"){@each(value, key in it.history){@li{@(value)}}}
  #|      @svg(~viewBox: "0 0 1 1"){@circle(~r: "1")}
  #|    }

///|
test "a component built from the compiled tree renders what the file says" {
  let views = @viewgen.read_file(ir_src, name="Ir")
  let from_tree = @component.component(
    name="IrFromTree",
    views=@viewgen.build_views(views.components[0], macros=views.macros),
    initial=ir_state(),
  )
  let got = strip_cid(render_comp(from_tree))
  // Every construct the reader has to reproduce, in the rendered output: a
  // constant and a dynamic attribute, a text slot, a guard on each side, an
  // `if` in an attribute, a loop, and a nested SVG namespace.
  assert_true(got.contains("<span id=\"count\">2</span>"), msg=got)
  assert_true(got.contains("<li>1</li><li>2</li>"), msg=got)
  assert_true(got.contains("title=\"Counter\""), msg=got)
  assert_true(got.contains("shown"), msg=got)
  assert_false(got.contains("hidden"), msg=got)
  assert_true(got.contains("class=\"on\""), msg=got)
  assert_true(got.contains("<circle r=\"1\">"), msg=got)
}

///|
test "handlers dispatch through a compiled tree" {
  let views = @viewgen.read_file(ir_src, name="Ir")
  let comp = @component.component(
    name="IrDispatch",
    views=@viewgen.build_views(views.components[0], macros=views.macros),
    initial=ir_state(),
    update=(s : IrState, msg, _ctx) => {
      match msg {
        Receive("add", [Num(d)]) => Next({ ..s, count: s.count + d.to_int(), })
        _ => Unhandled
      }
    },
  )
  let scope = @component.ComponentStack::new()
  scope.register_components([comp])
  scope.compile_all()
  // The event table survived the round trip: the renderer finds the handler
  // for the element's data-eid, which is what a real DOM click resolves.
  guard! comp.get_view(None) is Some(view)
  guard! view.ctx is Some(px)
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
  let out = StringBuilder()
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

///|
/// A macro declared in the FILE, expanded by the reader into the compiled
/// tree, renders the same markup a runtime-registered one does.
///
/// This was the second differential — the same view once with a file macro and
/// once with the body registered from MoonBit — and it went with the notation:
/// there is no printed macro body for a `@anode.Macro` to be built from any
/// more, because a view arrives EXPANDED. What is left is the claim it was
/// standing in for: the call's argument reaches the body, and the call's `tone`
/// beats the macro's default.
let macro_view_src : String =
  #|spec:
  #|  Badge:
  #|    field title :: String
  #|
  #|view:
  #|  macro badge(~tone: "plain", ~label: ""):
  #|    @span(~class: "badge", ~data_tone: tone){@(label)}
  #|
  #|  Badge:
  #|    @div{@badge(~label: it.title, ~tone: "loud")}

///|
priv struct BadgeState {
  title : String
}

///|
test "a file-declared macro is expanded into the compiled tree" {
  let vs = @viewgen.read_file(macro_view_src, name="Badge")
  let from_tree = @component.component(
    name="BadgeTree",
    views=@viewgen.build_views(vs.components[0], macros=vs.macros),
    initial=BadgeState::{ title: "hi", },
  )
  let got = strip_cid(render_comp(from_tree))
  assert_true(got.contains("data-tone=\"loud\""), msg=got)
  assert_true(got.contains(">hi</span>"), msg=got)
  assert_true(got.contains("class=\"badge\""), msg=got)
}

///|
impl @component.Fields for IrState with fn encode(s) {
  {
    "label": Str(s.label),
    "count": Num(s.count.to_double()),
    "history": (
      List(s.history.map(x => (Num(x.to_double()) : @tutuca.Value))) :
      @tutuca.Value),
  }
}

///|
impl @component.Fields for IrState with fn decode(f) {
  guard f.get("label") is Some(Str(v_label)) else { return None }
  guard f.get("count") is Some(Num(n_count)) else { return None }
  let v_count = n_count.to_int()
  guard f.get("history") is Some(List(l_history)) else { return None }
  let v_history : Array[Int] = []
  for x in l_history {
    guard x is Num(n) else { return None }
    v_history.push(n.to_int())
  }
  Some({ label: v_label, count: v_count, history: v_history, })
}

///|
impl @component.Fields for BadgeState with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for BadgeState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  Some({ title: v_title, })
}

///|
impl @component.Fields for IrState with fn schema() {
  @component.SchemaInfo::new(fingerprint="ir_state", fields=[
    @component.FieldInfo::new("label", TyText),
    @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
    @component.FieldInfo::new("history", TyList(TyInt(width=32, signed=true))),
  ])
}

///|
impl @component.Fields for BadgeState with fn schema() {
  @component.SchemaInfo::new(fingerprint="badge_state", fields=[
    @component.FieldInfo::new("title", TyText),
  ])
}
