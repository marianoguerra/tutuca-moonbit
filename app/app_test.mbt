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
} derive(ToJson, FromJson)

///|
fn item_comp() -> @component.Component {
  @component.component(
    name="Item",
    view="<li><span><x text=\".label\"></x></span><button @on.click=\"pick 'gold'\">pick</button></li>",
    init=ItemState::{ label: "plain" },
    update=(_s : ItemState, msg, _ctx) => {
      match msg {
        Input("pick", [Str(l)]) => Some({ label: l })
        Response("load", [Str(l), _]) => Some({ label: l })
        _ => None
      }
    },
  )
}

///|
priv struct PanelState {
  title : String
} derive(ToJson, FromJson)

///|
fn panel_comp() -> @component.Component {
  @component.component(
    name="Panel",
    view="<div><h1><x text=\".title\"></x></h1><x render=\".item\"></x></div>",
    init=PanelState::{ title: "panel" },
    specs={ "item": @component.FieldSpec::comp("Item") },
  )
}

///|
fn item_label(tx : @transactor.Transactor) -> @tutuca.Value {
  match
    @tutuca.Path::new(steps=[FieldStep("item"), FieldStep("label")]).lookup(
      tx.root,
    ) {
    Some(n) => n.as_value().unwrap_or(Null)
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
  // the rebuilt stack, dispatch through the Input channel
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_true(item_label(tx) == Str("gold"))
  // the old root is untouched (COW instances)
  assert_true(
    root.field("item") is Obj(o) && o.obj_field("label") == Some(Str("plain")),
  )
  // re-render from the new root shows the change
  guard tx.root.as_value() is Some(new_root) else { fail("root not a value") }
  let container2 = mount(scope.comps, new_root)
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
test "requests resolve through the component's registration scope" {
  let scope = @component.ComponentStack::new()
  scope.register_components([item_comp(), panel_comp()])
  scope.register_request_handlers({
    "load": RequestFn((_args, respond) => respond(Ok(Str("from-request")))),
  })
  scope.compile_all()
  guard scope.lookup_component("Panel") is Some(panel) else {
    fail("Panel missing")
  }
  let root = panel.make(Map([]))
  let tx = @transactor.Transactor::new(root, requests=@app.ScopeRequests::{
    comps: scope.comps,
  })
  // request at the item's path: handler found via the scope chain, the
  // response lands on the item's Response bucket
  tx.push_request(@tutuca.DispatchPath::of_steps([FieldStep("item")]), "load", [])
  assert_true(item_label(tx) == Str("from-request"))
  // unknown requests respond with the not-found error (no handler -> no-op
  // here since Item has no matching response bucket entry)
  let before = tx.root
  tx.push_request(@tutuca.DispatchPath::of_steps([FieldStep("item")]), "nope", [])
  assert_true(physical_equal(tx.root, before))
}
