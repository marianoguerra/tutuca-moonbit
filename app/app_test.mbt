// Static end-to-end (A1 acceptance): real components registered through a
// scope, rendered to the in-memory DOM, a click reconstructed and dispatched
// through the transactor, the state change asserted and re-rendered.

///|
fn find_el(
  root : @memdom.MemNode,
  tag : String,
  nth? : Int = 0,
) -> @memdom.MemNode? {
  let hits : Array[@memdom.MemNode] = []
  fn walk(n : @memdom.MemNode) {
    if n.tag == tag {
      hits.push(n)
    }
    for c in n.childs {
      walk(c)
    }
  }

  walk(root)
  hits.get(nth)
}

///|
fn mount(
  comps : @component.Components,
  root_val : @tutuca.Value,
) -> @memdom.MemNode raise {
  let stack = @render.RenderStack::new(root_val, comps~)
  let ctx = @render.RenderCtx::new(view_resolver=comps)
  guard @render.render_root(root_val, stack, ctx) is Some(v) else {
    fail("root did not render")
  }
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _ = @vdom.render(v, container, @vdom.RenderOpts::new(doc))
  container
}

///|
priv struct ItemState {
  label : String
}

///|
fn item_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<li><span><x text=\".label\"></x></span><button @on.click=\"pick 'gold'\">pick</button></li>",
      ),
    },
    name="Item",
    init=ItemState::{ label: "plain", },
    update=(_s : ItemState, msg, _ctx) => {
      match msg {
        Receive("pick", [Str(l)]) => Next({ label: l, })
        Receive("loadOk", [Str(l), ..]) => Next({ label: l, })
        _ => Unhandled
      }
    },
  )
}

///|
priv struct PanelState {
  title : String
}

///|
fn panel_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><h1><x text=\".title\"></x></h1><x render=\".item\"></x></div>",
      ),
    },
    name="Panel",
    init=PanelState::{ title: "panel", },
  )
}

///|
fn item_label(tx : @transactor.Transactor) -> @tutuca.Value {
  match
    @tutuca.Path::new(steps=[FieldStep("item"), FieldStep("label")]).lookup(
      tx.root,
    ) {
    Some(n) => n
    None => Null
  }
}

///|
test "static e2e: register -> render -> click -> dispatch -> re-render" {
  let scope = @component.ComponentStack::new()
  scope.register_components([item_comp(), panel_comp()])
  scope.compile_all()
  guard scope.lookup_component("Panel") is Some(panel) else {
    fail("Panel missing")
  }
  let root = panel.make({ "title": Str("Board") })
  let container = mount(scope.comps, root)
  // rendered through real component views, item made via FComp default
  assert_true(container.to_html().contains("plain"))
  assert_true(container.to_html().contains("Board"))
  let tx = @transactor.Transactor::new(root)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  // click: reconstruct (real metas), evaluate the parsed 'gold' arg against
  // the rebuilt stack, dispatch as an addressed message
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_true(item_label(tx) == Str("gold"))
  // the old root is untouched (COW instances)
  assert_true(
    root.field("item") is Obj(o) && o.obj_field("label") == Some(Str("plain")),
  )
  // re-render from the new root shows the change
  let container2 = mount(scope.comps, tx.root)
  assert_true(container2.to_html().contains("gold"))
}

///|
test "no matching handler leaves everything untouched" {
  let scope = @component.ComponentStack::new()
  scope.register_components([item_comp(), panel_comp()])
  scope.compile_all()
  guard scope.lookup_component("Panel") is Some(panel) else {
    fail("Panel missing")
  }
  let root = panel.make(Map([]))
  let container = mount(scope.comps, root)
  let tx = @transactor.Transactor::new(root)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  let before = tx.root
  assert_false(
    @app.dispatch_dom_event(tx, btn, "keydown", container, scope.comps),
  )
  assert_true(physical_equal(tx.root, before))
}

///|
impl @component.Fields for ItemState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for ItemState with fn decode(f) {
  guard f.get("label") is Some(Str(v_label)) else { return None }
  Some({ label: v_label, })
}

///|
impl @component.Fields for PanelState with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for PanelState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  Some({ title: v_title, })
}

///|
impl @component.Fields for ItemState with fn schema() {
  @component.SchemaInfo::new(fingerprint="item_state", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
impl @component.Fields for PanelState with fn schema() {
  @component.SchemaInfo::new(fingerprint="panel_state", fields=[
    @component.FieldInfo::new("title", TyText),
    @component.FieldInfo::new("item", TyComp(Some("Item"))),
  ])
}

// ---------------------------------------------------------------------------
// v2: the DOM entry and the lexical leg.

///|
test "a view raises a message, and the lexical leg answers an intent" {
  // Two halves in one drive. The DOM entry pushes a `Receive`, the ADDRESSED
  // bucket that holds a view's own `@on` name and a parent's `ctx.send` alike,
  // and `ScopeIntents` resolves the `lex` leg through the component's
  // REGISTRATION scope, answering with the whole chain instead of one handler.
  let asked : Array[String] = []
  let scope = @component.ComponentStack::new()
  scope.register_intent_handlers({
    "loadRows": [
      IntentFn((_call, answer) => {
        asked.push("first")
        answer(Pass)
      }),
      IntentFn((call, answer) => {
        asked.push("second@\{call.from.items.length()}")
        answer(Ok(Str("rows")))
      }),
    ],
  })
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button class=\"go\" @on.click=\"go\">go</button><span class=\"seen\" @text=\".seen\"></span></div>",
      ),
    },
    name="Lexy",
    init=LexyState::{ seen: "", },
    update=(_s : LexyState, msg, ctx) => {
      match msg {
        // The view's name arrives as a MESSAGE now.
        Receive("go", _) => {
          ctx.intent(
            "loadRows",
            [],
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="loadRowsOk"),
          )
          Unchanged
        }
        // ...and the answer arrives as one too.
        Receive("loadRowsOk", [v]) => Next({ seen: v.to_repr().to_string(), })
        _ => Unhandled
      }
    },
  )
  scope.register_components([comp])
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = @app.App::new(
    scope,
    comp.make(Map([])),
    container,
    @vdom.RenderOpts::new(doc),
  )
  app.start()
  guard find_el(container, "BUTTON") is Some(btn) else {
    fail("no button rendered")
  }
  let _ = app.dispatch(btn, @render.DomEvent::new(name="click"))
  // The first scope handler declined and the second answered — a walk, not a
  // lookup — and `from` carried the sender's position.
  assert_eq(asked.join(","), "first,second@0")
  assert_true(container.to_html().contains("rows"))
}

///|
priv struct LexyState {
  seen : String
}

///|
impl @component.Fields for LexyState with fn encode(s) {
  { "seen": Str(s.seen) }
}

///|
impl @component.Fields for LexyState with fn decode(f) {
  guard f.get("seen") is Some(Str(v)) else { return None }
  Some({ seen: v, })
}

///|
impl @component.Fields for LexyState with fn schema() {
  @component.SchemaInfo::new(fingerprint="lexy_state", fields=[
    @component.FieldInfo::new("seen", TyText),
  ])
}
