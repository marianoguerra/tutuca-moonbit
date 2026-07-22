// Component core tests (ports of oo.test.js / components.test.js subsets):
// typed-state make/coercion/defaults, generated mutators, the update
// Dispatch bucket, registration scopes + aliases, provide/lookup
// compilation, styles, and the hybrid seam (a for_type struct component
// next to a typed-state one).

///|
priv struct TodoState {
  title : String
  done : Bool
  count : Int
  items : Array[@tutuca.Value]
  tags : Map[String, @tutuca.Value]
} derive(ToJson, FromJson)

///|
fn todo_comp() -> @component.Component {
  @component.component(
    name="Todo",
    view="<div><x text=\".title\"></x></div>",
    init=TodoState::{
      title: "untitled",
      done: false,
      count: 0,
      items: [],
      tags: Map([]),
    },
    update=(s : TodoState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Some({ ..s, title: t })
        _ => None
      }
    },
  )
}

///|
test "make fills defaults and coerces args" {
  let comp = todo_comp()
  let t = comp.make({ "title": Str("a"), "done": Str("not-a-bool") })
  assert_true(t.field("title") == Str("a"))
  assert_true(t.field("done") == Bool(false)) // wrong shape -> default
  assert_true(t.field("count") == Num(0))
  assert_true(t.field("items") == List([]))
  // unknown args are ignored
  let u = comp.make({ "nope": Str("x") })
  assert_true(u.field("nope") == Null)
}

///|
test "generated mutators: set/toggle/update/push/setAt/delete/len/reset" {
  let comp = todo_comp()
  let t0 = comp.make(Map([]))
  guard t0 is Obj(o) else { fail("not obj") }
  guard o.obj_field("setTitle") is Some(Fn(set_title)) else {
    fail("no setTitle")
  }
  let t1 = set_title([Null, Str("x")])
  assert_true(t1.field("title") == Str("x"))
  assert_true(t0.field("title") == Str("untitled")) // COW
  guard t1 is Obj(o1) else { fail("not obj") }
  guard o1.obj_field("toggleDone") is Some(Fn(toggle)) else {
    fail("no toggleDone")
  }
  guard toggle([Null]) is Obj(o2) else { fail("toggle did not return obj") }
  assert_true(o2.obj_field("done") == Some(Bool(true)))
  guard o1.obj_field("updateCount") is Some(Fn(upd)) else {
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
  guard o1.obj_field("pushInItems") is Some(Fn(push)) else { fail("no push") }
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
  guard o1.obj_field("resetTitle") is Some(Fn(reset)) else { fail("no reset") }
  guard reset([Null]) is Obj(o7) else { fail("reset failed") }
  assert_true(o7.obj_field("title") == Some(Str("untitled")))
}

///|
priv struct NoFields {} derive(ToJson, FromJson)

///|
test "set slot field: coercion + addIn/hasIn/toggleIn/deleteIn/len mutators" {
  let comp = @component.component(
    name="Facets",
    view="<div></div>",
    init=NoFields::{  },
    // default set of two members; a List arg coerces (and dedups) into the
    // Map-backed set, Bool(true) values keyed by member.
    specs={ "sel": @component.FieldSpec::set(members=["a", "b"]) },
  )
  // default
  let t = comp.make(Map([]))
  assert_true(t.field("sel") == Map({ "a": Bool(true), "b": Bool(true) }))
  // coerce a List arg (with a duplicate) into a deduped set
  let t2 = comp.make({ "sel": List([Str("x"), Str("x"), Str("y")]) })
  assert_true(t2.field("sel") == Map({ "x": Bool(true), "y": Bool(true) }))
  guard t is Obj(o)
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
priv struct SetInState {
  sel : Map[String, Bool]
} derive(ToJson, FromJson)

///|
test "FSet kind override for a typed S field keeps the typed default" {
  let comp = @component.component(
    name="TypedFacets",
    view="<div></div>",
    init=SetInState::{ sel: { "a": true } },
    specs={ "sel": @component.FieldSpec::set() },
  )
  let t = comp.make(Map([]))
  assert_true(t.field("sel") == Map({ "a": Bool(true) }))
  guard t is Obj(o)
  // set-kind mutators exist because the kind was overridden
  guard o.obj_field("addInSel") is Some(Fn(add))
  guard add([Null, Str("b")]) is Obj(o2)
  assert_true(
    o2.obj_field("sel").unwrap() == Map({ "a": Bool(true), "b": Bool(true) }),
  )
}

///|
test "omap slot field: keyed mutators over an ordered Map" {
  let comp = @component.component(
    name="Ordered",
    view="<div></div>",
    init=NoFields::{  },
    specs={ "m": @component.FieldSpec::omap(default={ "x": Num(1) }) },
  )
  let t = comp.make(Map([]))
  assert_true(t.field("m") == Map({ "x": Num(1) }))
  // wrong-shape arg falls back to default
  assert_true(comp.make({ "m": Str("no") }).field("m") == Map({ "x": Num(1) }))
  guard t is Obj(o)
  guard o.obj_field("setInMAt") is Some(Fn(set_at))
  guard set_at([Null, Str("y"), Num(2)]) is Obj(o2)
  assert_true(o2.obj_field("m").unwrap() == Map({ "x": Num(1), "y": Num(2) }))
  guard o.obj_field("deleteInMAt") is Some(Fn(del))
  guard del([Null, Str("x")]) is Obj(o3)
  assert_true(o3.obj_field("m").unwrap() == Map(Map([])))
}

///|
test "Components::collect_classes gathers sorted classes from compiled views" {
  let scope = @component.ComponentStack::new()
  let a = @component.component(
    name="A",
    view="<div class=\"foo bar\"><span class=\"bar\">x</span></div>",
    init=NoFields::{  },
  )
  let b = @component.component(name="B", view="<p class=\"baz qux\">y</p>", init=NoFields::{

  })
  scope.register_components([a, b])
  scope.compile_all()
  // union of every literal class across both components' compiled views, sorted
  inspect(scope.comps.collect_classes().join(","), content="bar,baz,foo,qux")
}

///|
test "update dispatches through Path::update; Input falls back to mutators" {
  let comp = todo_comp()
  let t = comp.make({ "title": Str("a") })
  let root : @tutuca.Value = Map({ "todo": t })
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
priv struct CountOnly {
  count : Int
} derive(ToJson, FromJson)

///|
test "mutate and compute buckets surface as pre-bound Fns" {
  let comp = @component.component(
    name="Counter",
    view="<div></div>",
    init=CountOnly::{ count: 1 },
    mutate={ "inc": (s : CountOnly, _args) => { count: s.count + 1 } },
    compute={ "label": (s : CountOnly, _args) => Str("n=\{s.count}") },
  )
  let t = comp.make(Map([]))
  guard t is Obj(o)
  guard o.obj_field("label") is Some(Fn(label))
  assert_true(label([Null]) == Str("n=1"))
  guard o.obj_field("inc") is Some(Fn(inc))
  guard inc([Null]) is Obj(o2)
  assert_true(o2.obj_field("count") == Some(Num(2)))
  // and through Input dispatch (event position)
  let root : @tutuca.Value = Map({ "c": t })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("c")])
  let node2 = p.update(node, Input, "inc", [])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("c"), FieldStep("count")]).lookup(node2)
    is Some(n) &&
    n.as_value() == Some(Num(2)),
  )
}

///|
test "registration scopes: chains, aliases, sibling independence" {
  let root_scope = @component.ComponentStack::new()
  let a = @component.component(name="A", view="<i>a</i>", init=NoFields::{  })
  let b = @component.component(name="B", view="<i>b</i>", init=NoFields::{  })
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
priv struct TitleOnly {
  title : String
} derive(ToJson, FromJson)

///|
test "compile parses provide/lookup and stamps view ids" {
  let scope = @component.ComponentStack::new()
  let ws = @component.component(
    name="Workspace",
    view="<main><x text=\".title\"></x></main>",
    init=TitleOnly::{ title: "t" },
    provide={
      "active": ".sheet",
      "sel": ".sheets[.selId]",
      "bad": "not a field!",
    },
    lookup={
      "active": { source: "Workspace.active", default: Some(".fallback") },
      "broken": { source: "nodot", default: None },
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
    init=NoFields::{  },
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
priv struct LabelOnly {
  label : String
} derive(ToJson, FromJson)

///|
test "FComp slot fields default through the registration scope" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(name="Child", view="<i>c</i>", init=LabelOnly::{
    label: "hi",
  })
  let parent = @component.component(
    name="Parent",
    view="<div><x render=\".kid\"></x></div>",
    init=NoFields::{  },
    specs={ "kid": @component.FieldSpec::comp("Child") },
  )
  scope.register_components([child, parent])
  let p = parent.make(Map([]))
  guard p.field("kid") is Obj(o) else { fail("kid not made") }
  assert_true(o.obj_field("label") == Some(Str("hi")))
}

///|
priv struct StashedState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
test "Value fields in S carry Obj instances losslessly through updates" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(name="Leaf", view="<i>l</i>", init=LabelOnly::{
    label: "leaf",
  })
  let parent = @component.component(
    name="Holder",
    view="<div></div>",
    init=StashedState::{ items: [] },
    update=(s : StashedState, msg, _ctx) => {
      match msg {
        Receive("add", [item, ..]) => Some({ items: s.items + [item] })
        _ => None
      }
    },
  )
  scope.register_components([child, parent])
  let leaf = child.make(Map([]))
  let holder = parent.make(Map([]))
  let root : @tutuca.Value = Map({ "h": holder })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("h")])
  let node2 = p.update(node, Receive, "add", [leaf])
  guard @tutuca.Path::new(steps=[FieldStep("h"), FieldStep("items")]).lookup(
      node2,
    )
    is Some(n) &&
    n.as_value() is Some(List(items)) else {
    fail("items not found")
  }
  // the child instance survived the typed-state round-trip as the SAME Obj
  guard items[0] is Obj(o) else { fail("child lost in round-trip") }
  assert_true(o.obj_field("label") == Some(Str("leaf")))
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
        Handler((args, _ctx) => {
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
    scope.comps.get_comp_for(todo.make(Map([]))) is Some(c2) &&
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

///|
priv struct FilterState {
  query : String
} derive(ToJson, FromJson)

///|
test "typed render-time buckets: when/enrich/enrich_scope/loop_with" {
  let comp = @component.component(
    name="Filtered",
    view="<ul><li @each=\".items\" @when=\"keep\" @enrich-with=\"annotate\" @loop-with=\"page\"></li></ul>",
    init=FilterState::{ query: "a" },
    when={
      "keep": (s : FilterState, _key, value, _iter) => {
        value.str().contains(s.query)
      },
    },
    enrich={
      "annotate": (_s : FilterState, binds, _key, value, _iter) => {
        binds["len"] = Num(value.str().length().to_double())
      },
    },
    enrich_scope={
      "derived": (s : FilterState) => { "upper": Str(s.query.to_upper()) },
    },
    loop_with={
      "page": (_s : FilterState, _seq, _ctx) => {
        @component.LoopWith::new(start=1, end=3)
      },
    },
  )
  let t = comp.make(Map([]))
  guard t is Obj(o)
  // @when: Fn-convention [this, key, value, iterData] -> Bool
  guard o.obj_render_handler("keep", Alter) is Fn(keep)
  assert_eq(keep([Null, Num(0), Str("cat")]), Bool(true))
  assert_eq(keep([Null, Num(0), Str("dog")]), Bool(false))
  // @enrich-with: mutates the binds map, return ignored
  guard o.obj_render_handler("annotate", Alter) is Fn(annotate)
  let binds : Map[String, @tutuca.Value] = {
    "key": Num(0),
    "value": Str("cat"),
  }
  let _ = annotate([Null, Map(binds), Num(0), Str("cat"), Null])
  assert_eq(binds.get("len"), Some(Num(3)))
  // scope form: called with no args, returns the binds map
  guard o.obj_render_handler("derived", Alter) is Fn(derived)
  assert_eq(derived([Null]), Map({ "upper": Str("A") }))
  // @loop-with: returns the {start, end} plan the renderer unpacks
  guard o.obj_render_handler("page", Alter) is Fn(page)
  assert_eq(
    page([Null, List([]), Null]),
    Map({ "start": Num(1), "end": Num(3) }),
  )
}

///|
priv struct SwapAState {
  label : String
} derive(ToJson, FromJson)

///|
priv struct SwapBState {
  note : String
} derive(ToJson, FromJson)

///|
test "swap handlers replace the node with another component's instance" {
  let scope = @component.ComponentStack::new()
  let b = @component.component(name="BComp", view="<i @text=\".note\"></i>", init=SwapBState::{
    note: "i am b",
  })
  let a = @component.component(
    name="AComp",
    view="<button @on.click=\"becomeB\">go</button>",
    init=SwapAState::{ label: "a" },
    swap={
      "becomeB": (s : SwapAState, _args, _ctx) => {
        Some(b.make({ "note": Str("from \{s.label}") }))
      },
    },
  )
  scope.register_components([a, b])
  let inst = a.make(Map([]))
  let root : @tutuca.Value = Map({ "slot": inst })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("slot")])
  let node2 = p.update(node, Input, "becomeB", [])
  guard @tutuca.Path::new(steps=[FieldStep("slot"), FieldStep("note")]).lookup(
      node2,
    )
    is Some(n) &&
    n.as_value() is Some(Str(note)) else {
    fail("swap did not replace the node")
  }
  assert_eq(note, "from a")
  // metadata surfaces the swap bucket
  assert_true(a.swap_names.contains("becomeB"))
}
