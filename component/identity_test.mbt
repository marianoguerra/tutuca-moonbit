// Instance identity: what survives a state write, and what the survivors buy.
//
// Encoding a state struct round-trips it through Json, which rebuilds every
// container even when nothing about it changed. Identity is what the render
// cache and Path copy-on-write read, so a rebuilt-but-equal list would
// silently invalidate a subtree that did not move. instance.mbt therefore
// keeps the OLD object wherever the new one is structurally equal, and hands
// back the ORIGINAL instance when nothing changed at all — which is what makes
// a no-op update free all the way up to the root.
//
// These tests observe that from outside the package, through Value identity.

///|
priv struct IdState {
  title : String
  count : Int
  items : Array[@tutuca.Value]
  tags : Map[String, @tutuca.Value]
}

///|
fn id_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".title\"></x></div>",
      ),
    },
    name="Ided",
    init=IdState::{ title: "untitled", count: 0, items: [], tags: Map([]) },
    update=(s : IdState, msg, _ctx) => {
      match msg {
        // returns a struct that is EQUAL to the current state
        Receive("touch", _) => Some({ ..s })
        Receive("rename", [Str(t)]) => Some({ ..s, title: t })
        _ => None
      }
    },
  )
}

///|
fn seeded() -> @tutuca.Value {
  id_comp().make({
    "title": Str("hello"),
    "count": Num(2),
    "items": List([Str("a"), Str("b")]),
    "tags": Map({ "x": Bool(true) }),
  })
}

///|
/// Send `name` at `v` and return the resulting node, or `v` when the handler
/// reported no change.
fn send(
  v : @tutuca.Value,
  name : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  @tutuca.Path::new().update(v, Receive, name, args)
}

///|
test "an instance presents the SAME Value every time it is asked" {
  // Each `Obj(self)` cast allocates, so without memoizing, an instance would
  // look different every time it crossed the value seam — and every cache
  // entry keyed on it would miss.
  let v = seeded()
  guard v is Obj(o)
  guard o.obj_field("title") is Some(_)
  // reading a field back out of the tree yields the same object
  let again = send(v, "nothing-matches-this", [])
  assert_true(physical_equal(again, v))
}

///|
test "a write that changes nothing returns the ORIGINAL instance" {
  let v = seeded()
  let after = send(v, "touch", [])
  assert_true(physical_equal(after, v))
}

///|
test "a field set to the value it already holds returns the same instance" {
  let v = seeded()
  guard v is Obj(o)
  // $setTitle with the current title — the shape a re-fired `input` event takes
  guard o.obj_with_field("title", Str("hello")) is Some(same)
  assert_true(physical_equal(same, v))
  // …and via the generated mutator the views actually call
  guard o.obj_field("setTitle") is Some(Fn(set_title))
  assert_true(physical_equal(set_title([Null, Str("hello")]), v))
}

///|
test "an untouched field keeps its exact Value object across a change" {
  // `rename` rewrites `title` only. `items` and `tags` are rebuilt by the Json
  // round trip, so the ONLY reason they can still be the same objects is the
  // reuse-if-equal comparison — and that is what stops a rewrite of `title`
  // from propagating a brand-new root and scheduling a re-render.
  let v = seeded()
  guard v is Obj(before)
  guard before.obj_field("items") is Some(items_before)
  guard before.obj_field("tags") is Some(tags_before)
  guard before.obj_field("count") is Some(count_before)
  let after = send(v, "rename", [Str("goodbye")])
  assert_false(physical_equal(after, v)) // it really did change
  guard after is Obj(o)
  guard o.obj_field("items") is Some(items_after)
  guard o.obj_field("tags") is Some(tags_after)
  guard o.obj_field("count") is Some(count_after)
  assert_true(physical_equal(items_before, items_after))
  assert_true(physical_equal(tags_before, tags_after))
  assert_true(physical_equal(count_before, count_after))
}

///|
test "the changed field is correct, and is a new object" {
  let v = seeded()
  guard v is Obj(before)
  guard before.obj_field("title") is Some(title_before)
  let after = send(v, "rename", [Str("goodbye")])
  guard after is Obj(o)
  @debug.assert_eq(o.obj_field("title"), Some(Str("goodbye")))
  guard o.obj_field("title") is Some(title_after)
  assert_false(physical_equal(title_before, title_after))
  // the original is untouched — state is immutable, not mutated in place
  @debug.assert_eq(before.obj_field("title"), Some(Str("hello")))
}

///|
test "identity is preserved through a nested list, not just at the top" {
  // A parent holding child instances: rewriting one child must leave the
  // others' Values alone, or every sibling's cached subtree is invalidated.
  let child = id_comp()
  let parent = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Parent",
    init=IdState::{ title: "p", count: 0, items: [], tags: Map([]) },
  )
  let kids = [
    child.make({ "title": Str("one") }),
    child.make({ "title": Str("two") }),
    child.make({ "title": Str("three") }),
  ]
  let v = parent.make({ "items": List(kids) })
  guard v is Obj(o)
  // rewrite the middle child through the parent's list mutator
  guard o.obj_field("setInItemsAt") is Some(Fn(set_at))
  let renamed = send(kids[1], "rename", [Str("TWO")])
  let after = set_at([Null, Num(1), renamed])
  guard after is Obj(o2)
  guard o2.obj_field("items") is Some(List(items))
  assert_eq(items.length(), 3)
  // the untouched siblings are the very same objects
  assert_true(physical_equal(items[0], kids[0]))
  assert_true(physical_equal(items[2], kids[2]))
  // and the rewritten one took
  assert_true(physical_equal(items[1], renamed))
  guard items[1] is Obj(mid)
  @debug.assert_eq(mid.obj_field("title"), Some(Str("TWO")))
}

///|
test "writing a list back unchanged leaves the parent instance alone" {
  let child = id_comp()
  let parent = @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Parent",
    init=IdState::{ title: "p", count: 0, items: [], tags: Map([]) },
  )
  let kids = [child.make({ "title": Str("one") })]
  let v = parent.make({ "items": List(kids) })
  guard v is Obj(o)
  guard o.obj_field("setInItemsAt") is Some(Fn(set_at))
  // set index 0 to the object already there: a fresh List is built and then
  // discarded, because it is equal to the one stored.
  assert_true(physical_equal(set_at([Null, Num(0), kids[0]]), v))
}

///|
impl @component.Fields for IdState with fn encode(s) {
  {
    "title": Str(s.title),
    "count": Num(s.count.to_double()),
    "items": (List(s.items) : @tutuca.Value),
    "tags": (Map(s.tags) : @tutuca.Value),
  }
}

///|
impl @component.Fields for IdState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  guard f.get("count") is Some(Num(n_count)) else { return None }
  let v_count = n_count.to_int()
  guard f.get("items") is Some(List(v_items)) else { return None }
  guard f.get("tags") is Some(Map(v_tags)) else { return None }
  Some(IdState::{ title: v_title, count: v_count, items: v_items, tags: v_tags })
}

///|
impl @component.Fields for IdState with fn schema() {
  @component.SchemaInfo::new(fingerprint="id_state", fields=[
    @component.FieldInfo::new("title", TyText),
    @component.FieldInfo::new("count", TyInt),
    @component.FieldInfo::new("items", TyList(TyAny)),
    @component.FieldInfo::new("tags", TyOMap(TyAny)),
  ])
}
