// Component core tests (ports of oo.test.js / components.test.js subsets):
// make/coercion/defaults, generated mutators, registration scopes + aliases,
// provide/lookup compilation, styles, and the hybrid seam (a typed-struct
// component next to a component() one).

///|
fn todo_comp() -> @component.Component {
  @component.component(
    name="Todo",
    view="<div><x text=\".title\"></x></div>",
    fields={
      "title": @component.FieldSpec::of_default(Str("untitled")),
      "done": @component.FieldSpec::of_default(Bool(false)),
      "count": @component.FieldSpec::of_default(Num(0)),
      "items": @component.FieldSpec::of_default(List([])),
      "tags": @component.FieldSpec::of_default(Map({})),
    },
    receive={
      "rename": (inst, args, _ctx) => {
        match args {
          [Str(s)] => Some(inst.set("title", Str(s)))
          _ => None
        }
      },
    },
  )
}

///|
test "make fills defaults and coerces args" {
  let comp = todo_comp()
  let t = comp.make({ "title": Str("a"), "done": Str("not-a-bool") })
  assert_true(t.get("title") == Str("a"))
  assert_true(t.get("done") == Bool(false)) // wrong shape -> default
  assert_true(t.get("count") == Num(0))
  assert_true(t.get("items") == List([]))
  // unknown args are ignored
  let u = comp.make({ "nope": Str("x") })
  assert_true(u.get("nope") == Null)
}

///|
test "generated mutators: set/toggle/update/push/setAt/delete/len/reset" {
  let comp = todo_comp()
  let t0 = comp.make({})
  let t1 = t0.set("title", Str("x"))
  assert_true(t1.get("title") == Str("x"))
  assert_true(t0.get("title") == Str("untitled")) // COW
  // via generated method Fns (pre-bound, this-slot dropped)
  guard t1.to_value() is Obj(o) else { fail("not obj") }
  guard o.obj_field("toggleDone") is Some(Fn(toggle)) else {
    fail("no toggleDone")
  }
  guard toggle([Null]) is Obj(o2) else { fail("toggle did not return obj") }
  assert_true(o2.obj_field("done") == Some(Bool(true)))
  guard o.obj_field("updateCount") is Some(Fn(upd)) else {
    fail("no updateCount")
  }
  let bump : @tutuca.Value = Fn(args => {
    match args {
      [Num(n)] => Num(n + 1)
      _ => Num(-1)
    }
  })
  guard upd([Null, bump]) is Obj(o3) else { fail("update failed") }
  assert_true(o3.obj_field("count") == Some(Num(1)))
  guard o.obj_field("pushInItems") is Some(Fn(push)) else { fail("no push") }
  guard push([Null, Str("a")]) is Obj(o4) else { fail("push failed") }
  assert_true(o4.obj_field("items") == Some(List([Str("a")])))
  guard o4.obj_field("setInItemsAt") is Some(Fn(set_at)) else {
    fail("no setAt")
  }
  guard set_at([Null, Num(0), Str("b")]) is Obj(o5) else {
    fail("setAt failed")
  }
  assert_true(o5.obj_field("items") == Some(List([Str("b")])))
  guard o5.obj_field("deleteInItemsAt") is Some(Fn(del)) else { fail("no del") }
  guard del([Null, Num(0)]) is Obj(o6) else { fail("del failed") }
  assert_true(o6.obj_field("items") == Some(List([])))
  guard o4.obj_field("itemsLen") is Some(Fn(len)) else { fail("no len") }
  assert_true(len([Null]) == Num(1))
  guard o.obj_field("resetTitle") is Some(Fn(reset)) else { fail("no reset") }
  guard reset([Null]) is Obj(o7) else { fail("reset failed") }
  assert_true(o7.obj_field("title") == Some(Str("untitled")))
}

///|
test "set field: coercion + addIn/hasIn/toggleIn/deleteIn/len mutators" {
  let comp = @component.component(name="Facets", view="<div></div>", fields={
    // default set of two members; a List arg coerces (and dedups) into the
    // Map-backed set, Bool(true) values keyed by member.
    "sel": @component.FieldSpec::set(members=["a", "b"]),
  })
  // default
  let t = comp.make({})
  assert_true(t.get("sel") == Map({ "a": Bool(true), "b": Bool(true) }))
  // coerce a List arg (with a duplicate) into a deduped set
  let t2 = comp.make({ "sel": List([Str("x"), Str("x"), Str("y")]) })
  assert_true(t2.get("sel") == Map({ "x": Bool(true), "y": Bool(true) }))
  guard t.to_value() is Obj(o)
  // hasIn
  guard o.obj_field("hasInSel") is Some(Fn(has))
  assert_true(has([Null, Str("a")]) == Bool(true))
  assert_true(has([Null, Str("z")]) == Bool(false))
  // addIn
  guard o.obj_field("addInSel") is Some(Fn(add))
  guard add([Null, Str("c")]) is Obj(o2)
  assert_true(o2.obj_field("hasInSel").unwrap() is Fn(_))
  assert_true(
    o2.obj_field("sel").unwrap() ==
    Map({ "a": Bool(true), "b": Bool(true), "c": Bool(true) }),
  )
  // toggleIn removes an existing member, adds a missing one
  guard o.obj_field("toggleInSel") is Some(Fn(toggle))
  guard toggle([Null, Str("a")]) is Obj(o3)
  assert_true(o3.obj_field("sel").unwrap() == Map({ "b": Bool(true) }))
  guard toggle([Null, Str("q")]) is Obj(o4)
  assert_true(
    o4.obj_field("sel").unwrap() ==
    Map({ "a": Bool(true), "b": Bool(true), "q": Bool(true) }),
  )
  // deleteIn / removeIn alias
  guard o.obj_field("deleteInSel") is Some(Fn(del))
  guard del([Null, Str("b")]) is Obj(o5)
  assert_true(o5.obj_field("sel").unwrap() == Map({ "a": Bool(true) }))
  assert_true(o.obj_field("removeInSel").unwrap() is Fn(_))
  // len is the generic sized mutator
  guard o.obj_field("selLen") is Some(Fn(len))
  assert_true(len([Null]) == Num(2))
}

///|
test "omap field: keyed mutators over an ordered Map" {
  let comp = @component.component(name="Ordered", view="<div></div>", fields={
    "m": @component.FieldSpec::omap(default={ "x": Num(1) }),
  })
  let t = comp.make({})
  assert_true(t.get("m") == Map({ "x": Num(1) }))
  // wrong-shape arg falls back to default
  assert_true(comp.make({ "m": Str("no") }).get("m") == Map({ "x": Num(1) }))
  guard t.to_value() is Obj(o)
  guard o.obj_field("setInMAt") is Some(Fn(set_at))
  guard set_at([Null, Str("y"), Num(2)]) is Obj(o2)
  assert_true(o2.obj_field("m").unwrap() == Map({ "x": Num(1), "y": Num(2) }))
  guard o.obj_field("deleteInMAt") is Some(Fn(del))
  guard del([Null, Str("x")]) is Obj(o3)
  assert_true(o3.obj_field("m").unwrap() == Map({}))
}

///|
test "Components::collect_classes gathers sorted classes from compiled views" {
  let scope = @component.ComponentStack::new()
  let a = @component.component(
    name="A",
    view="<div class=\"foo bar\"><span class=\"bar\">x</span></div>",
  )
  let b = @component.component(name="B", view="<p class=\"baz qux\">y</p>")
  scope.register_components([a, b])
  scope.compile_all()
  // union of every literal class across both components' compiled views, sorted
  inspect(scope.comps.collect_classes().join(","), content="bar,baz,foo,qux")
}

///|
test "bucket handlers dispatch through Path::update with $unknown untouched" {
  let comp = todo_comp()
  let t = comp.make({ "title": Str("a") })
  let root : @tutuca.Value = Map({ "todo": t.to_value() })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("todo")])
  let node2 = p.update(node, Receive, "rename", [Str("b")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("todo"), FieldStep("title")]).lookup(
      node2,
    )
    is Some(n) &&
    n.as_value() == Some(Str("b")),
  )
  // Input falls back to generated mutators (pre-app-loop convenience)
  let node3 = p.update(node, Input, "setTitle", [Str("via-input")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("todo"), FieldStep("title")]).lookup(
      node3,
    )
    is Some(n2) &&
    n2.as_value() == Some(Str("via-input")),
  )
}

///|
test "registration scopes: chains, aliases, sibling independence" {
  let root_scope = @component.ComponentStack::new()
  let a = @component.component(name="A", view="<i>a</i>")
  let b = @component.component(name="B", view="<i>b</i>")
  root_scope.register_components([a], aliases={ "Alias": "A" })
  guard a.scope is Some(a_scope) else { fail("no scope on A") }
  // A's own (child) scope sees the registration scope's entries
  assert_true(a_scope.lookup_component("A") is Some(_))
  assert_true(a_scope.lookup_component("Alias") is Some(_))
  // a sibling scope registered elsewhere is invisible
  let other = root_scope.enter()
  other.register_components([b])
  assert_true(a_scope.lookup_component("B") is None)
  guard b.scope is Some(b_scope) else { fail("no scope on B") }
  assert_true(b_scope.lookup_component("A") is Some(_)) // parent chain
}

///|
test "compile parses provide/lookup and stamps view ids" {
  let scope = @component.ComponentStack::new()
  let ws = @component.component(
    name="Workspace",
    view="<main><x text=\".title\"></x></main>",
    fields={ "title": @component.FieldSpec::of_default(Str("t")) },
    provide={
      "active": ".sheet",
      "sel": ".sheets[.selId]",
      "bad": "not a field!",
    },
    lookup={
      "active": @component.LookupSpec::{
        source: "Workspace.active",
        default: Some(".fallback"),
      },
      "broken": @component.LookupSpec::{ source: "nodot", default: None },
    },
  )
  scope.register_components([ws])
  scope.compile_all()
  assert_true(ws.provide.get("active") is Some(p) && p.val is Field("sheet"))
  assert_true(
    ws.provide.get("sel") is Some(p2) &&
    p2.val is SeqAccess(seq="sheets", key="selId"),
  )
  assert_true(ws.provide.get("bad") is None) // bad shape dropped
  assert_true(
    ws.lookup.get("active") is Some(lk) &&
    lk.comp_name == "Workspace" &&
    lk.provide_name == "active" &&
    lk.default_val is Some(Field("fallback")),
  )
  assert_true(ws.lookup.get("broken") is None)
  // producer-key memoization (JS LookupInfo._sym): Pending until first resolve,
  // then Done with the producer's provide key — Workspace.active resolves to
  // its own provide "active".
  guard ws.lookup.get("active") is Some(lk2)
  assert_true(lk2.producer_key is Pending)
  guard ws.provide.get("active") is Some(prov)
  let resolved = lk2.resolve_producer_key(ws.scope)
  assert_true(resolved == Some(prov.key))
  assert_true(lk2.producer_key is Done(Some(_)))
  // second call returns the memoized value
  assert_true(lk2.resolve_producer_key(ws.scope) == Some(prov.key))
  // the compiled view stamped data-cid/data-vid on its root
  guard ws.get_view(None) is Some(v) && v.anode is Some(_) else {
    fail("view not compiled")
  }
}

///|
test "compile_style emits data-cid scoped blocks" {
  let comp = @component.component(
    name="Styled",
    view="<div>x</div>",
    style="color: red",
    common_style="border: 0",
    global_style="body{margin:0}",
  )
  let css = comp.compile_style()
  assert_true(css.contains("[data-cid=\"\{comp.id}\"]{border: 0}"))
  assert_true(css.contains("body{margin:0}"))
  assert_true(
    css.contains("[data-cid=\"\{comp.id}\"][data-vid=\"main\"]{color: red}"),
  )
}

///|
test "FComp fields default through the registration scope" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(name="Child", view="<i>c</i>", fields={
    "label": @component.FieldSpec::of_default(Str("hi")),
  })
  let parent = @component.component(
    name="Parent",
    view="<div><x render=\".kid\"></x></div>",
    fields={ "kid": @component.FieldSpec::comp("Child") },
  )
  scope.register_components([child, parent])
  let p = parent.make({})
  guard p.get("kid") is Obj(o) else { fail("kid not made") }
  assert_true(o.obj_field("label") == Some(Str("hi")))
}

///|
/// The typed-struct half of the hybrid: a plain struct implementing Obj,
/// registered through the same scope via Component::for_type.
priv struct Badge {
  cid : Int
  label : String
}

///|
impl @tutuca.Obj for Badge with fn component_id(self) {
  Some(self.cid)
}

///|
impl @tutuca.Obj for Badge with fn obj_field(self, name) {
  match name {
    "label" => Some(Str(self.label))
    _ => None
  }
}

///|
impl @tutuca.Obj for Badge with fn obj_handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "relabel") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(s)] =>
              Some(
                (Obj(Badge::{ cid: self.cid, label: s }) : @tutuca.Value)
                as &@tutuca.PathNode,
              )
            _ => None
          }
        }),
      )
    _ => None
  }
}

///|
test "hybrid: a typed-struct component registers and dispatches alongside" {
  let scope = @component.ComponentStack::new()
  let badge_comp = @component.Component::for_type(
    name="Badge",
    view="<span><x text=\".label\"></x></span>",
  )
  let todo = todo_comp()
  scope.register_components([badge_comp, todo])
  let badge : @tutuca.Value = Obj(Badge::{ cid: badge_comp.id, label: "new" })
  // the registry resolves both hybrid halves from their values
  assert_true(scope.comps.get_comp_for(badge) is Some(c) && c.name == "Badge")
  assert_true(
    scope.comps.get_comp_for(todo.make({}).to_value()) is Some(c2) &&
    c2.name == "Todo",
  )
  // and the typed struct dispatches through the same path machinery
  let root : @tutuca.Value = Map({ "badge": badge })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("badge")])
  let node2 = p.update(node, Receive, "relabel", [Str("gold")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("badge"), FieldStep("label")]).lookup(
      node2,
    )
    is Some(n) &&
    n.as_value() == Some(Str("gold")),
  )
}
