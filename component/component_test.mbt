// Component core tests:
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
}

///|
fn todo_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".title\"></x></div>",
      ),
    },
    name="Todo",
    init=TodoState::{
      title: "untitled",
      done: false,
      count: 0,
      items: [],
      tags: Map([]),
    },
    update=(s : TodoState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Next({ ..s, title: t, })
        _ => Unhandled
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
test "generated mutators: set/toggle/push/setAt/delete/len/reset" {
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
test "member actions hide generated mutator spellings" {
  let t0 = todo_comp().make(Map([]))
  guard! t0.set_member("title", Str("named")) is PChanged(t1)
  assert_eq(t1.field("title"), Str("named"))
  guard! t1.mutate_member("items", "push", [Str("a")]) is PChanged(t2)
  assert_eq(t2.field("items"), List([Str("a")]))
  guard! t2.mutate_member("items", "removeAt", [Num(0)]) is PChanged(t3)
  assert_eq(t3.field("items"), List([]))
  guard! t3.set_member("done", Bool(true)) is PChanged(t4)
  assert_eq(t4.field("done"), Bool(true))
  assert_true(t4.mutate_member("items", "frobnicate", []) is PMissing)
}

///|
priv struct NoFields {} derive(Default)

///|
/// A component whose only field is a closed set the STRUCT does not hold —
/// declared, so its members are its default.
priv struct FacetsOnly {} derive(Default)

///|
priv struct OMapInState {
  m : Map[String, @tutuca.Value]
}

///|
/// A parent whose only field is a child-component slot.
priv struct ParentWithKid {} derive(Default)

///|
/// A parent whose slot is declared as the bare `component` marker — "a component
/// slot" with no name, which is what a state block spells when the name is not
/// spellable there. `slots~` is the only place the name can come from.
priv struct ParentWithAnyKid {} derive(Default)

///|
test "set slot field: coercion + addIn/hasIn/toggleIn/deleteIn/len mutators" {
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Facets",
    // The state's own value, not the type's: `TyFlags` says which members are
    // spellable, and the declaration says which ones are set to begin with.
    init=FacetsOnly::{ },
  )
  // default
  let t = comp.make(Map([]))
  assert_true(t.field("sel") == Map({ "a": Bool(true), "b": Bool(true) }))
  // coerce a List arg (with a duplicate) into a deduped set
  let t2 = comp.make({ "sel": List([Str("x"), Str("x"), Str("y")]) })
  assert_true(t2.field("sel") == Map({ "x": Bool(true), "y": Bool(true) }))
  guard! t is Obj(o)
  // hasIn
  guard! o.obj_field("hasInSel") is Some(Fn(has))
  assert_true(has([Null, Str("a")]) == Bool(true))
  assert_true(has([Null, Str("z")]) == Bool(false))
  // addIn
  guard! o.obj_field("addInSel") is Some(Fn(add))
  // Adding an existing member is a no-op all the way through core's COW map.
  assert_true(physical_equal(add([Null, Str("a")]), t))
  guard! add([Null, Str("c")]) is Obj(o2)
  assert_true(o2.obj_field("hasInSel").unwrap() is Fn(_))
  assert_true(
    o2.obj_field("sel").unwrap() ==
    Map({ "a": Bool(true), "b": Bool(true), "c": Bool(true) }),
  )
  // toggleIn removes an existing member, adds a missing one
  guard! o.obj_field("toggleInSel") is Some(Fn(toggle))
  guard! toggle([Null, Str("a")]) is Obj(o3)
  assert_true(o3.obj_field("sel").unwrap() == Map({ "b": Bool(true) }))
  guard! toggle([Null, Str("q")]) is Obj(o4)
  assert_true(
    o4.obj_field("sel").unwrap() ==
    Map({ "a": Bool(true), "b": Bool(true), "q": Bool(true) }),
  )
  // deleteIn / removeIn alias
  guard! o.obj_field("deleteInSel") is Some(Fn(del))
  assert_true(physical_equal(del([Null, Str("missing")]), t))
  guard! del([Null, Str("b")]) is Obj(o5)
  assert_true(o5.obj_field("sel").unwrap() == Map({ "a": Bool(true) }))
  assert_true(o.obj_field("removeInSel").unwrap() is Fn(_))
  // len is the generic sized mutator
  guard! o.obj_field("selLen") is Some(Fn(len))
  assert_true(len([Null]) == Num(2))
}

///|
priv struct SetInState {
  sel : Map[String, Bool]
}

///|
test "a declared set keeps the typed default and gets set mutators" {
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="TypedFacets",
    init=SetInState::{ sel: { "a": true }, },
  )
  let t = comp.make(Map([]))
  assert_true(t.field("sel") == Map({ "a": Bool(true) }))
  guard! t is Obj(o)
  // set-kind mutators exist because the SCHEMA declares `sel` a set
  guard! o.obj_field("addInSel") is Some(Fn(add))
  guard! add([Null, Str("b")]) is Obj(o2)
  assert_true(
    o2.obj_field("sel").unwrap() == Map({ "a": Bool(true), "b": Bool(true) }),
  )
}

///|
test "omap slot field: keyed mutators over an ordered Map" {
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Ordered",
    // A non-empty default is a VALUE, so it comes from `init` rather than from
    // a spec beside the type.
    init=OMapInState::{ m: { "x": Num(1) }, },
  )
  let t = comp.make(Map([]))
  assert_true(t.field("m") == Map({ "x": Num(1) }))
  // wrong-shape arg falls back to default
  assert_true(comp.make({ "m": Str("no") }).field("m") == Map({ "x": Num(1) }))
  guard! t is Obj(o)
  guard! o.obj_field("setInMAt") is Some(Fn(set_at))
  guard! set_at([Null, Str("y"), Num(2)]) is Obj(o2)
  assert_true(o2.obj_field("m").unwrap() == Map({ "x": Num(1), "y": Num(2) }))
  guard! o.obj_field("deleteInMAt") is Some(Fn(del))
  // A key that is not there is a no-op that hands back the SAME object, not an
  // equal one: the transactor reads `physical_equal` as "nothing happened" and
  // skips the spine rebuild, so identity is the contract rather than equality.
  assert_true(physical_equal(del([Null, Str("missing")]), t))
  guard! del([Null, Str("x")]) is Obj(o3)
  assert_true(o3.obj_field("m").unwrap() == Map(Map([])))
}

///|
test "Components::collect_classes gathers sorted classes from compiled views" {
  let scope = @component.ComponentStack::new()
  let a = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"foo bar\"><span class=\"bar\">x</span></div>",
      ),
    },
    name="A",
    init=NoFields::{ },
  )
  let b = @component.component(
    views={
      "main": @anode.View::new("main", raw_view="<p class=\"baz qux\">y</p>"),
    },
    name="B",
    init=NoFields::{ },
  )
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
  let node : @tutuca.Value = root
  let p = @tutuca.Path::new(steps=[FieldStep("todo")])
  let node2 = p.update(node, Receive, "rename", [Str("b")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("todo"), FieldStep("title")]).lookup(
      node2,
    )
    is Some(n) &&
    n == Str("b"),
  )
  // Input falls back to generated mutators (pre-app-loop convenience)
  let node3 = p.update(node, Receive, "setTitle", [Str("via-input")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("todo"), FieldStep("title")]).lookup(
      node3,
    )
    is Some(n2) &&
    n2 == Str("via-input"),
  )
}

///|
priv struct CountOnly {
  count : Int
}

///|
test "a compute entry is a pre-bound Fn; an update arm is not" {
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Counter",
    init=CountOnly::{ count: 1, },
    update=(s : CountOnly, msg, _ctx) => {
      match msg {
        Receive("inc", _) => Next({ count: s.count + 1, })
        _ => Unhandled
      }
    },
    compute={ "label": (s : CountOnly, _args, _stack) => Str("n=\{s.count}") },
  )
  let t = comp.make(Map([]))
  guard! t is Obj(o)
  // A `compute` entry is reachable in a VALUE position — that is what the
  // bucket is for, and why an update arm cannot replace it: there is no
  // event and no ctx there.
  guard! o.obj_field("label") is Some(Fn(label))
  assert_true(label([Null]) == Str("n=1"))
  // An `update` arm is NOT: it answers a dispatch, not a field read.
  assert_true(o.obj_field("inc") is None)
  // ...and it does answer through Input dispatch (event position).
  let root : @tutuca.Value = Map({ "c": t })
  let node : @tutuca.Value = root
  let p = @tutuca.Path::new(steps=[FieldStep("c")])
  let node2 = p.update(node, Receive, "inc", [])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("c"), FieldStep("count")]).lookup(node2)
    is Some(n) &&
    n == Num(2),
  )
}

///|
test "registration scopes: chains, aliases, sibling independence" {
  let root_scope = @component.ComponentStack::new()
  let root_theme = @tutuca.Path::new(steps=[FieldStep("session")])
  root_scope.register_paths({ "theme": root_theme })
  let a = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>a</i>") },
    name="A",
    init=NoFields::{ },
  )
  let b = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>b</i>") },
    name="B",
    init=NoFields::{ },
  )
  root_scope.register_components([a], aliases={ "Alias": "A" })
  guard a.scope is Some(a_scope) else { fail("no scope on A") }
  // A's own (child) scope sees the registration scope's entries
  assert_true(a_scope.lookup_component("A") is Some(_))
  assert_true(a_scope.lookup_component("Alias") is Some(_))
  assert_eq(a_scope.lookup_path("theme"), Some(root_theme))
  let local_theme = @tutuca.Path::new(steps=[FieldStep("previewTheme")])
  a_scope.register_paths({ "theme": local_theme, "Theme": root_theme })
  assert_eq(a_scope.lookup_path("theme"), Some(local_theme))
  assert_true(a_scope.lookup_path("Theme") is None)
  // a sibling scope registered elsewhere is invisible
  let other = root_scope.enter()
  other.register_components([b])
  assert_true(a_scope.lookup_component("B") is None)
  guard b.scope is Some(b_scope) else { fail("no scope on B") }
  assert_true(b_scope.lookup_component("A") is Some(_)) // parent chain
}

///|
test "ModuleDef registers lexical value paths outside the root component" {
  let consumer = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i></i>") },
    name="PathConsumer",
    init=NoFields::{ },
    lookup=[@component.lookup_name("session")],
  )
  let session = @tutuca.Path::new(steps=[FieldStep("session")])
  let module_def = @component.ModuleDef::new(
    name="path-module",
    components=[consumer],
    paths={ "session": session },
  )
  let _scope = module_def.build_scope()
  guard consumer.scope is Some(consumer_scope) else {
    fail("consumer has no registration scope")
  }
  assert_eq(consumer_scope.lookup_path("session"), Some(session))
  assert_true(consumer.provide.is_empty())
}

///|
priv struct TitleOnly {
  title : String
}

///|
test "compile parses provide/lookup and stamps view ids" {
  let scope = @component.ComponentStack::new()
  let ws = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x text=\".title\"></x></main>",
      ),
    },
    name="Workspace",
    init=TitleOnly::{ title: "t", },
    provide={
      "active": ".sheet",
      "sel": ".sheets[.selId]",
      "bad": "not a field!",
      "Cell": "self",
      "Nope": ".sheet",
    },
    lookup=[
      @component.lookup_or("active", ".fallback"),
      @component.lookup_name("theme"),
    ],
  )
  scope.register_components([ws])
  scope.compile_all()
  assert_true(
    ws.provide.get("active") is Some(p) &&
    p.val is ERead(place={ root: PState("sheet"), steps: [], .. }, ..),
  )
  assert_true(
    ws.provide.get("sel") is Some(p2) &&
    p2.val
    is ERead(
      place={
        root: PState("sheets"),
        steps: [
          PIndex(ERead(place={ root: PState("selId"), steps: [], .. }, ..)),
        ],
        ..
      },
      ..
    ),
  )
  assert_true(ws.provide.get("bad") is None) // bad shape dropped
  // An uppercase key publishes a TYPE, and lands in the other map. `"self"` is
  // the only value one can take, so `Nope` is dropped the way `bad` is.
  assert_true(ws.provide.get("Cell") is None)
  assert_true(ws.provide_type.get("Cell") == Some(ws.id))
  assert_true(ws.provide_type.get("Nope") is None)
  assert_true(
    ws.lookup.get("active") is Some(lk) &&
    lk.default_val
    is Some(ERead(place={ root: PState("fallback"), steps: [], .. }, ..)),
  )
  // A lookup with no default carries none, and is still declared.
  assert_true(ws.lookup.get("theme") is Some(lk2) && lk2.default_val is None)
  // Producer discovery is deliberately absent: the render stack records the
  // concrete path when it evaluates a provide.
  // the compiled view stamped data-cid/data-vid on its root
  guard ws.get_view(None) is Some(v) && v.anode is Some(_) else {
    fail("view not compiled")
  }
}

///|
test "compile_style emits data-cid scoped blocks" {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div>x</div>",
        style="color: red",
      ),
    },
    name="Styled",
    init=NoFields::{ },
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
}

///|
test "FComp slot fields default through the registration scope" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>c</i>") },
    name="Child",
    init=LabelOnly::{ label: "hi", },
  )
  let parent = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".kid\"></x></div>",
      ),
    },
    name="Parent",
    // The slot is DECLARED, the way a state block declares one; the component
    // it holds is part of the field's type.
    init=ParentWithKid::{ },
  )
  scope.register_components([child, parent])
  let p = parent.make(Map([]))
  guard p.field("kid") is Obj(o) else { fail("kid not made") }
  assert_true(o.obj_field("label") == Some(Str("hi")))
}

///|
/// A schema can say "a component slot" without saying WHICH — the bare
/// `component` marker — because a name like `DnDExample` is not spellable in the
/// block (kebab-case cannot round-trip it). `slots~` is then the only place the
/// name can come from, and before this it was read and dropped: the slot stayed
/// Null and the child never rendered.
test "slots~ names a slot the schema declared as bare `component`" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>c</i>") },
    name="DNDExample",
    init=LabelOnly::{ label: "hi", },
  )
  let parent = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".kid\"></x></div>",
      ),
    },
    name="Parent",
    init=ParentWithAnyKid::{ },
    slots={ "kid": "DNDExample" },
    slot_args={ "kid": { "label": Str("named through slots") } },
  )
  scope.register_components([child, parent])
  let p = parent.make(Map([]))
  guard p.field("kid") is Obj(o) else { fail("kid not made through slots~") }
  assert_true(o.obj_field("label") == Some(Str("named through slots")))
  // the descriptor carries the resolved name, so the inspector and structural
  // equality see the same slot the runtime built
  guard parent.schema.field("kid") is Some(fi) else {
    fail("kid not in schema")
  }
  assert_true(fi.ty == TyComp(Some("DNDExample")))
}

///|
/// The other direction: a slot the schema NAMES is not overridable. A caller
/// saying something different from the declared type would leave every reader of
/// the descriptor disagreeing with the block.
test "slots~ does not override a slot the schema already names" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>c</i>") },
    name="Child",
    init=LabelOnly::{ label: "declared", },
  )
  let other = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<b>o</b>") },
    name="Other",
    init=LabelOnly::{ label: "usurper", },
  )
  let parent = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".kid\"></x></div>",
      ),
    },
    name="Parent",
    // the schema says Child; this says Other, and the schema wins
    init=ParentWithKid::{ },
    slots={ "kid": "Other" },
  )
  scope.register_components([child, other, parent])
  let p = parent.make(Map([]))
  guard p.field("kid") is Obj(o) else { fail("kid not made") }
  assert_true(o.obj_field("label") == Some(Str("declared")))
}

///|
priv struct StashedState {
  items : Array[@tutuca.Value]
}

///|
test "Value fields in S carry Obj instances losslessly through updates" {
  let scope = @component.ComponentStack::new()
  let child = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<i>l</i>") },
    name="Leaf",
    init=LabelOnly::{ label: "leaf", },
  )
  let parent = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Holder",
    init=StashedState::{ items: [], },
    update=(s : StashedState, msg, _ctx) => {
      match msg {
        Receive("add", [item, ..]) => Next({ items: s.items + [item], })
        _ => Unhandled
      }
    },
  )
  scope.register_components([child, parent])
  let leaf = child.make(Map([]))
  let holder = parent.make(Map([]))
  let root : @tutuca.Value = Map({ "h": holder })
  let node : @tutuca.Value = root
  let p = @tutuca.Path::new(steps=[FieldStep("h")])
  let node2 = p.update(node, Receive, "add", [leaf])
  guard @tutuca.Path::new(steps=[FieldStep("h"), FieldStep("items")]).lookup(
      node2,
    )
    is Some(n) &&
    n is List(items) else {
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
              Some((Obj(Badge::{ cid: self.cid, label: s, }) : @tutuca.Value))
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
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<span><x text=\".label\"></x></span>",
      ),
    },
    name="Badge",
    // Hand-written and complete: the struct answers `.label` and one Receive,
    // and this says so. `for_type` requires it for the same reason `component`
    // does — being hand-written is not being under-described.
    schema=@component.SchemaInfo::new(
      fingerprint="badge-test",
      fields=[@component.FieldInfo::new("label", TyText)],
      receives=["relabel"],
      view_names=["main"],
    ),
  )
  let todo = todo_comp()
  scope.register_components([badge_comp, todo])
  let badge : @tutuca.Value = Obj(Badge::{ cid: badge_comp.id, label: "new", })
  // the registry resolves both hybrid halves from their values
  assert_true(scope.comps.get_comp_for(badge) is Some(c) && c.name == "Badge")
  assert_true(
    scope.comps.get_comp_for(todo.make(Map([]))) is Some(c2) &&
    c2.name == "Todo",
  )
  // and the typed struct dispatches through the same path machinery
  let root : @tutuca.Value = Map({ "badge": badge })
  let node : @tutuca.Value = root
  let p = @tutuca.Path::new(steps=[FieldStep("badge")])
  let node2 = p.update(node, Receive, "relabel", [Str("gold")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("badge"), FieldStep("label")]).lookup(
      node2,
    )
    is Some(n) &&
    n == Str("gold"),
  )
}

///|
priv struct FilterState {
  query : String
}

///|
test "typed render-time buckets: when/enrich/enrich_scope/loop_with" {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<ul><li @each=\".items\" @when=\"keep\" @enrich-with=\"annotate\" @loop-with=\"page\"></li></ul>",
      ),
    },
    name="Filtered",
    init=FilterState::{ query: "a", },
    when={
      "keep": (s : FilterState, _key, value, _iter, _stack) => {
        value.str().contains(s.query)
      },
    },
    enrich={
      "annotate": (_s : FilterState, binds, _key, value, _iter, _stack) => {
        binds["len"] = Num(value.str().length().to_double())
      },
    },
    enrich_scope={
      "derived": (s : FilterState, _stack) => {
        "upper": Str(s.query.to_upper()),
      },
    },
    loop_with={
      "page": (_s : FilterState, _seq, _ctx) => {
        @component.LoopWith::new(start=1, end=3)
      },
    },
  )
  let t = comp.make(Map([]))
  guard! t is Obj(o)
  // @when: Fn-convention [this, key, value, iterData] -> Bool
  guard! o.trigger("keep") is Some(Fn(keep))
  assert_eq(keep([Null, Num(0), Str("cat")]), Bool(true))
  assert_eq(keep([Null, Num(0), Str("dog")]), Bool(false))
  // @enrich-with: mutates the binds map, return ignored
  guard! o.trigger("annotate") is Some(Fn(annotate))
  let binds : Map[String, @tutuca.Value] = {
    "key": Num(0),
    "value": Str("cat"),
  }
  let _ = annotate([Null, Map(binds), Num(0), Str("cat"), Null])
  assert_eq(binds.get("len"), Some(Num(3)))
  // scope form: called with no args, returns the binds map
  guard! o.trigger("derived") is Some(Fn(derived))
  assert_eq(derived([Null]), Map({ "upper": Str("A") }))
  // @loop-with: returns the {start, end} plan the renderer unpacks
  guard! o.trigger("page") is Some(Fn(page))
  assert_eq(
    page([Null, List([]), Null]),
    Map({ "start": Num(1), "end": Num(3) }),
  )
}

///|
priv struct SwapAState {
  label : String
}

///|
priv struct SwapBState {
  note : String
}

///|
test "swap handlers replace the node with another component's instance" {
  let scope = @component.ComponentStack::new()
  let b = @component.component(
    views={
      "main": @anode.View::new("main", raw_view="<i @text=\".note\"></i>"),
    },
    name="BComp",
    init=SwapBState::{ note: "i am b", },
  )
  let a = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<button @on.click=\"becomeB\">go</button>",
      ),
    },
    name="AComp",
    init=SwapAState::{ label: "a", },
    swap={
      "becomeB": (s : SwapAState, _args, _ctx) => {
        Some(b.make({ "note": Str("from \{s.label}") }))
      },
    },
  )
  scope.register_components([a, b])
  let inst = a.make(Map([]))
  let root : @tutuca.Value = Map({ "slot": inst })
  let node : @tutuca.Value = root
  let p = @tutuca.Path::new(steps=[FieldStep("slot")])
  let node2 = p.update(node, Receive, "becomeB", [])
  guard @tutuca.Path::new(steps=[FieldStep("slot"), FieldStep("note")]).lookup(
      node2,
    )
    is Some(n) &&
    n is Str(note) else {
    fail("swap did not replace the node")
  }
  assert_eq(note, "from a")
  // metadata surfaces the swap bucket
  assert_true(a.swap_names.contains("becomeB"))
}

///|
impl @component.Fields for TodoState with fn encode(s) {
  {
    "title": Str(s.title),
    "done": Bool(s.done),
    "count": Num(s.count.to_double()),
    "items": (List(s.items) : @tutuca.Value),
    "tags": (Map(s.tags) : @tutuca.Value),
  }
}

///|
impl @component.Fields for TodoState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  guard f.get("done") is Some(Bool(v_done)) else { return None }
  guard f.get("count") is Some(Num(n_count)) else { return None }
  let v_count = n_count.to_int()
  guard f.get("items") is Some(List(v_items)) else { return None }
  guard f.get("tags") is Some(Map(v_tags)) else { return None }
  Some({
    title: v_title,
    done: v_done,
    count: v_count,
    items: v_items,
    tags: v_tags,
  })
}

///|
impl @component.Fields for NoFields with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for NoFields with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for SetInState with fn encode(s) {
  {
    "sel": {
      let m : Map[String, @tutuca.Value] = Map([])
      for k, b in s.sel {
        m[k] = Bool(b)
      }
      (Map(m) : @tutuca.Value)
    },
  }
}

///|
impl @component.Fields for SetInState with fn decode(f) {
  guard f.get("sel") is Some(Map(m_sel)) else { return None }
  let v_sel : Map[String, Bool] = Map([])
  for k2, x in m_sel {
    v_sel[k2] = x is Bool(true)
  }
  Some({ sel: v_sel, })
}

///|
impl @component.Fields for CountOnly with fn encode(s) {
  { "count": Num(s.count.to_double()) }
}

///|
impl @component.Fields for CountOnly with fn decode(f) {
  guard f.get("count") is Some(Num(n_count)) else { return None }
  let v_count = n_count.to_int()
  Some({ count: v_count, })
}

///|
impl @component.Fields for TitleOnly with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for TitleOnly with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  Some({ title: v_title, })
}

///|
impl @component.Fields for LabelOnly with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for LabelOnly with fn decode(f) {
  guard f.get("label") is Some(Str(v_label)) else { return None }
  Some({ label: v_label, })
}

///|
impl @component.Fields for StashedState with fn encode(s) {
  { "items": (List(s.items) : @tutuca.Value) }
}

///|
impl @component.Fields for StashedState with fn decode(f) {
  guard f.get("items") is Some(List(v_items)) else { return None }
  Some({ items: v_items, })
}

///|
impl @component.Fields for FilterState with fn encode(s) {
  { "query": Str(s.query) }
}

///|
impl @component.Fields for FilterState with fn decode(f) {
  guard f.get("query") is Some(Str(v_query)) else { return None }
  Some({ query: v_query, })
}

///|
impl @component.Fields for SwapAState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for SwapAState with fn decode(f) {
  guard f.get("label") is Some(Str(v_label)) else { return None }
  Some({ label: v_label, })
}

///|
impl @component.Fields for SwapBState with fn encode(s) {
  { "note": Str(s.note) }
}

///|
impl @component.Fields for SwapBState with fn decode(f) {
  guard f.get("note") is Some(Str(v_note)) else { return None }
  Some({ note: v_note, })
}

///|
impl @component.Fields for TodoState with fn schema() {
  @component.SchemaInfo::new(fingerprint="todo_state", fields=[
    @component.FieldInfo::new("title", TyText),
    @component.FieldInfo::new("done", TyBool),
    @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
    @component.FieldInfo::new("items", TyList(TyAny)),
    @component.FieldInfo::new("tags", TyOMap(TyAny)),
  ])
}

///|
impl @component.Fields for NoFields with fn schema() {
  @component.SchemaInfo::new(fingerprint="no_fields", fields=[])
}

///|
impl @component.Fields for ParentWithKid with fn schema() {
  @component.SchemaInfo::new(fingerprint="parent_with_kid", fields=[
    @component.FieldInfo::new("kid", TyComp(Some("Child"))),
  ])
}

///|
impl @component.Fields for ParentWithKid with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for ParentWithKid with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for ParentWithAnyKid with fn schema() {
  @component.SchemaInfo::new(fingerprint="parent_with_any_kid", fields=[
    @component.FieldInfo::new("kid", TyComp(None)),
  ])
}

///|
impl @component.Fields for ParentWithAnyKid with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for ParentWithAnyKid with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for FacetsOnly with fn schema() {
  @component.SchemaInfo::new(fingerprint="facets_only", fields=[
    @component.FieldInfo::new("sel", TyFlags("sel", ["a", "b"])),
  ])
}

///|
impl @component.Fields for FacetsOnly with fn encode(_s) {
  // The DECLARATION carries the default, not the type. A `TyFlags` describes
  // which members are spellable; the state says the default, the same way
  // every other field does.
  Map([("sel", Map({ "a": Bool(true), "b": Bool(true) }))])
}

///|
impl @component.Fields for FacetsOnly with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for OMapInState with fn schema() {
  @component.SchemaInfo::new(fingerprint="omap_in_state", fields=[
    @component.FieldInfo::new("m", TyOMap(TyAny)),
  ])
}

///|
impl @component.Fields for OMapInState with fn encode(s) {
  { "m": Map(s.m) }
}

///|
impl @component.Fields for OMapInState with fn decode(f) {
  guard f.get("m") is Some(Map(m)) else { return None }
  Some({ m, })
}

///|
impl @component.Fields for SetInState with fn schema() {
  @component.SchemaInfo::new(fingerprint="set_in_state", fields=[
    @component.FieldInfo::new("sel", TySet),
  ])
}

///|
impl @component.Fields for CountOnly with fn schema() {
  @component.SchemaInfo::new(fingerprint="count_only", fields=[
    @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
  ])
}

///|
impl @component.Fields for TitleOnly with fn schema() {
  @component.SchemaInfo::new(fingerprint="title_only", fields=[
    @component.FieldInfo::new("title", TyText),
  ])
}

///|
impl @component.Fields for LabelOnly with fn schema() {
  @component.SchemaInfo::new(fingerprint="label_only", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
impl @component.Fields for StashedState with fn schema() {
  @component.SchemaInfo::new(fingerprint="stashed_state", fields=[
    @component.FieldInfo::new("items", TyList(TyAny)),
  ])
}

///|
impl @component.Fields for FilterState with fn schema() {
  @component.SchemaInfo::new(fingerprint="filter_state", fields=[
    @component.FieldInfo::new("query", TyText),
  ])
}

///|
impl @component.Fields for SwapBState with fn schema() {
  @component.SchemaInfo::new(fingerprint="swap_b_state", fields=[
    @component.FieldInfo::new("note", TyText),
  ])
}

///|
impl @component.Fields for SwapAState with fn schema() {
  @component.SchemaInfo::new(fingerprint="swap_a_state", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

// ---------------------------------------------------------------------------
// v2: the widening, and the lexical walk.

///|
test "the widening: an addressed message reaches a generated mutator too" {
  // `swap` and the generated mutators answer `Receive`, the ADDRESSED bucket,
  // and nothing narrower. `@on.click="setTitle 'x'"` from the component's own
  // view and a parent's `ctx.send("setTitle", …)` to the same component are the
  // same message, so both reach the setter; gating on where the message came
  // from would admit one and refuse the other. Both arms below assert that.
  //
  // The consequence worth knowing: a `ctx.send` whose name happens to collide
  // with a generated mutator MUTATES. Names are the whole addressing scheme,
  // so a parent that did not mean the setter must not use the setter's name.
  let comp = todo_comp()
  let root : @tutuca.Value = Map({ "todo": comp.make({ "title": Str("a") }) })
  let p = @tutuca.Path::new(steps=[FieldStep("todo")])
  fn title(v : @tutuca.Value) -> @tutuca.Value {
    match
      @tutuca.Path::new(steps=[FieldStep("todo"), FieldStep("title")]).lookup(v) {
      Some(x) => x
      None => Null
    }
  }

  assert_eq(
    title(p.update(root, Receive, "setTitle", [Str("via-input")])),
    Str("via-input"),
  )
  assert_eq(
    title(p.update(root, Receive, "setTitle", [Str("via-send")])),
    Str("via-send"),
  )
  // And NOT up a route. A generated mutator answers a message at home; it is
  // not an answer to a question a descendant asked.
  assert_eq(
    title(p.update(root, Intent, "setTitle", [Str("via-intent")])),
    Str("a"),
  )
}

///|
/// A static handler that records that it was asked and then declines.
fn pass_fn(log : Array[String], tag : String) -> @component.IntentFn {
  IntentFn((_call, answer) => {
    log.push(tag)
    answer(Pass)
  })
}

///|
test "lookup_intent walks the scope chain and answers with the whole chain" {
  // Every handler visible for the name, innermost frame first — not just the
  // first match. An `IntentFn` may `Pass`, so a handler that declines is not
  // the end of the walk and every later candidate still has to be reachable.
  let log : Array[String] = []
  let root = @component.ComponentStack::new()
  root.register_intent_handlers({ "loadRows": [pass_fn(log, "root")] })
  let mid = root.enter()
  mid.register_intent_handlers({ "loadRows": [pass_fn(log, "mid")] })
  let leaf = mid.enter()
  leaf.register_intent_handlers({
    "loadRows": [pass_fn(log, "leaf-a"), pass_fn(log, "leaf-b")],
  })
  let chain = leaf.lookup_intent("loadRows")
  assert_eq(chain.length(), 4)
  for h in chain {
    let IntentFn(f) = h
    f({ name: "loadRows", args: [], from: @tutuca.DispatchPath::new(), }, _ => {
      ()
    })
  }
  // Innermost frame first, and registration order inside a frame.
  assert_eq(log.join(","), "leaf-a,leaf-b,mid,root")
  assert_eq(leaf.lookup_intent("nobodyDeclaresThis").length(), 0)
}

///|
test "two registrations of one intent name are two candidates, not a shadowing" {
  let log : Array[String] = []
  let scope = @component.ComponentStack::new()
  scope.register_intent_handlers({ "saveDraft": [pass_fn(log, "first")] })
  scope.register_intent_handlers({ "saveDraft": [pass_fn(log, "second")] })
  let chain = scope.lookup_intent("saveDraft")
  assert_eq(chain.length(), 2)
  for h in chain {
    let IntentFn(f) = h
    f({ name: "saveDraft", args: [], from: @tutuca.DispatchPath::new(), }, _ => {
      ()
    })
  }
  assert_eq(log.join(","), "first,second")
}

///|
/// A stack that answers one dynamic name, so a test can tell "the seam handed
/// the environment over" from "it handed over a `NullStack`".
priv struct OneBinding {
  name : String
  value : @tutuca.Value
}

///|
impl @tutuca.Stack for OneBinding with fn lookup_dynamic(self, name) {
  if name == self.name {
    self.value
  } else {
    Null
  }
}

///|
test "a compute is handed the stack it is asked from" {
  // The defect this covers: a `pred`/`compute` reading `*name` compiled into
  // `ctx.lookup(...)` inside a function with no `ctx` — because `ctx` is a
  // DISPATCH context and a value body is called while the view is being
  // rendered. What a value body needs is the render stack, and `Value::Fn`
  // carries arguments and nothing else — so `obj_method_at` is the seam that
  // hands one over.
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Themed",
    init=CountOnly::{ count: 1, },
    compute={
      "theme": (_s : CountOnly, _args, stack) => stack.lookup_dynamic("theme"),
    },
  )
  let t = comp.make(Map([]))
  guard! t is Obj(o)
  let stack : &@tutuca.Stack = OneBinding::{
    name: "theme",
    value: Str("dark"),
  }
  guard! o.obj_method_at("theme", stack) is Some(Fn(f))
  assert_true(f([Null]) == Str("dark"))
  // Asked WITHOUT one — a `$compute` read off a bare Value, outside any
  // render — it answers Null rather than guessing. That is the honest answer,
  // not a hole: there is no ancestry to walk from there.
  guard! o.obj_field("theme") is Some(Fn(g))
  assert_true(g([Null]) == Null)
}

///|
test "a @when is handed the stack too, through the alter seam" {
  // A `pred` used as a `@when` and the same `pred` used as `$name` are ONE
  // body compiled twice, so if one of them can read `*name` both must.
  let comp = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="ThemedWhen",
    init=CountOnly::{ count: 1, },
    when={
      "isTheme": (_s : CountOnly, _k, value, _iter, stack) => {
        stack.lookup_dynamic("theme") == value
      },
    },
  )
  let t = comp.make(Map([]))
  guard! t is Obj(o)
  let stack : &@tutuca.Stack = OneBinding::{
    name: "theme",
    value: Str("dark"),
  }
  guard! o.trigger_at("isTheme", stack) is Some(Fn(f))
  assert_true(f([Null, Null, Str("dark"), Null]) == Bool(true))
  assert_true(f([Null, Null, Str("light"), Null]) == Bool(false))
}

///|
/// `schema_writers` is the table minus the names that only read.
///
/// The two are one loop apart on purpose: a reader is recorded at the site
/// that installs it, so this cannot drift into listing a name the runtime does
/// not have — or missing one it does.
test "the generated table separates what writes from what only reads" {
  let schema = @component.SchemaInfo::new(fingerprint="writers", fields=[
    @component.FieldInfo::new("items", TyList(TyInt(width=32, signed=true))),
    @component.FieldInfo::new("tags", TySet),
    @component.FieldInfo::new("done", TyBool),
  ])
  let all = @component.schema_mutators(schema)
  let writers = @component.schema_writers(schema)
  // Every reader the loop installs is in the full table and out of this one.
  for reader in ["itemsLen", "tagsLen", "doneLen", "hasInTags"] {
    assert_true(all.contains(reader))
    assert_false(writers.contains(reader))
  }
  // …and nothing that writes was lost with them.
  for
    writer in [
      "setItems", "resetItems", "pushInItems", "insertInItemsAt", "setInItemsAt",
      "deleteInItemsAt", "removeInItemsAt", "addInTags", "deleteInTags", "toggleInTags",
      "toggleDone", "setDone",
    ] {
    assert_true(writers.contains(writer))
  }
  // The difference IS the readers, and nothing else.
  let dropped : Array[String] = []
  for name, _ in all {
    if !writers.contains(name) {
      dropped.push(name)
    }
  }
  // The difference IS the readers, and nothing else — length as well as
  // membership, so a writer quietly going missing fails here too.
  assert_eq(dropped.length(), 4)
  for expected in ["doneLen", "hasInTags", "itemsLen", "tagsLen"] {
    assert_true(dropped.contains(expected))
  }
}

///|
/// A reader dispatched as a message does nothing, which is what makes the
/// split above worth having rather than a matter of taste.
///
/// Both halves of the claim: `itemsLen` really is callable (it answers the
/// length through `$`), and sending it really does leave the instance exactly
/// where it was — the same instance, not an equal one.
test "sending a read-only generated name leaves the instance alone" {
  let comp = @component.component(name="Bag", views=Map([]), init=BagState::{
    items: [Num(1), Num(2), Num(3)],
  })
  let v = comp.make(Map([]))
  guard v is Obj(o) else { fail("a made component is an instance") }
  // It reads: `$itemsLen` answers three.
  guard o.trigger("itemsLen") is Some(Fn(f)) else {
    fail("itemsLen is a generated `$`-callable")
  }
  assert_eq(f([v]), Num(3))
  // It does not write: the dispatch is unclaimed, so the instance comes back
  // unchanged — physically, which is how the runtime says "nothing happened".
  let after = @tutuca.Path::new().update(v, Receive, "itemsLen", [])
  assert_true(physical_equal(after, v))
  // …whereas a writer from the same table does move it.
  let moved = @tutuca.Path::new().update(v, Receive, "pushInItems", [Num(4)])
  assert_false(physical_equal(moved, v))
}

///|
priv struct BagState {
  items : Array[@tutuca.Value]
}

///|
impl @component.Fields for BagState with fn encode(s) {
  { "items": List(s.items) }
}

///|
impl @component.Fields for BagState with fn decode(f) {
  guard f.get("items") is Some(List(a)) else { return None }
  Some({ items: a, })
}

///|
impl @component.Fields for BagState with fn schema() {
  @component.SchemaInfo::new(name="Bag", fingerprint="bag", fields=[
    @component.FieldInfo::new("items", TyList(TyAny)),
  ])
}
