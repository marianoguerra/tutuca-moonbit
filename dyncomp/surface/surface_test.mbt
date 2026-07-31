///| Blackbox tests over the patch algebra and the document format.
///
/// The algebra is the seam both layers drive, so its invariants are the ones
/// that have to hold for a human editor and a language model alike: a batch is
/// atomic, a tree stays a tree, and nothing is silently ignored.

///|
fn v(n : Int) -> @tutuca.Value {
  Num(n.to_double())
}

///|
fn sv(s : String) -> @tutuca.Value {
  Str(s)
}

///|
/// Apply, expecting success.
fn ok(s : Surface, ops : Array[SurfaceOp]) -> Surface {
  match apply(s, ops) {
    Ok(next) => next
    Err(errors) => {
      let shown = errors
        .map(e => "\{e.index} \{e.pointer}: \{e.message}")
        .join("; ")
      abort("expected success, got \{shown}")
    }
  }
}

///|
/// Apply, expecting failure, and render the errors for a snapshot.
fn failed(s : Surface, ops : Array[SurfaceOp]) -> Array[String] {
  match apply(s, ops) {
    Ok(_) => abort("expected failure, got success")
    Err(errors) => errors.map(e => "\{e.index} \{e.pointer}: \{e.message}")
  }
}

///|
test "a new surface is one empty stack" {
  let s = Surface::new("main")
  debug_inspect(s.walk(), content="[\"n0\"]")
  guard s.node("n0") is Some(root)
  debug_inspect(root.kind, content="Stack")
  inspect(
    root.container_style(),
    content="display:flex;flex-direction:column;flex-wrap:nowrap;justify-content:flex-start;align-items:stretch",
  )
}

///|
test "nodes are added, ordered, and reachable in document order" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    // index 0 puts it FIRST, which is what "insert above" means
    AddNode(parent="n0", index=0, kind=Box, props=Map([])),
  ])
  debug_inspect(s.walk(), content="[\"n0\", \"n3\", \"n1\", \"n2\"]")
}

///|
/// -1 appends, which is what "add one" means; an index past the end does the
/// same rather than failing, because the caller's intent is unambiguous.
test "an out-of-range index clamps instead of failing" {
  let s = Surface::new("main")
  let s = ok(s, [AddNode(parent="n0", index=99, kind=Slot, props=Map([]))])
  guard s.node("n0") is Some(root)
  debug_inspect(root.children, content="[\"n1\"]")
}

///|
/// The difference between a legible patch and a full node rewrite: changing
/// the gap does not restate the direction.
test "SetProps is partial" {
  let s = Surface::new("main")
  let s = ok(s, [
    SetProps(id="n0", props={ "direction": sv("row"), "gap": v(12) }),
  ])
  let s = ok(s, [SetProps(id="n0", props={ "gap": v(4) })])
  guard s.node("n0") is Some(root)
  debug_inspect(root.props.direction, content="Row")
  debug_inspect(root.props.gap, content="4")
}

///|
/// An ignored typo is a layout that silently did not change, and "why did
/// nothing happen" is the most expensive question a generated-UI loop can ask.
test "an unknown property is an error, not a shrug" {
  let s = Surface::new("main")
  debug_inspect(
    failed(s, [SetProps(id="n0", props={ "flexBasis": sv("2rem") })]),
    content=(
      #|["0 /nodes/n0/props/flexBasis: no such layout property (direction, wrap, justify, align, gap, padding, columns, rows, colSpan, rowSpan, colStart, rowStart, background, border)"]
    ),
  )
}

///|
test "a bad enum value says what it would have accepted" {
  let s = Surface::new("main")
  debug_inspect(
    failed(s, [
      SetProps(id="n0", props={ "direction": sv("sideways"), "gap": sv("wide") }),
    ]),
    content=(
      #|[
      #|  "0 /nodes/n0/props/direction: expected row | column | row-reverse | column-reverse, got sideways",
      #|  "0 /nodes/n0/props/gap: expected a number, got wide",
      #|]
    ),
  )
}

///|
/// A track list is three shapes, not a CSS length. Every excluded form —
/// minmax, repeat, percentages, calc — is a place a generated layout silently
/// collapses, and a substituted `auto` looks nearly right, which is harder to
/// notice than a refusal.
test "grid tracks accept fr, px and auto, and nothing else" {
  let s = Surface::new("main")
  let s2 = ok(s, [
    SetProps(id="n0", props={
      "columns": List([sv("1fr"), sv("240px"), sv("auto")]),
    }),
  ])
  guard s2.node("n0") is Some(root)
  debug_inspect(root.props.columns, content="[Fr(1), Px(240), Auto]")
  debug_inspect(
    failed(s, [
      SetProps(id="n0", props={
        "columns": List([sv("1fr"), sv("minmax(10px, 1fr)")]),
      }),
    ]),
    content=(
      #|["0 /nodes/n0/props/columns/1: expected a track: <n>fr | <n>px | auto, got minmax(10px, 1fr)"]
    ),
  )
}

///|
test "a grid renders its track lists; a stack renders its flex" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Grid, props={
      "columns": List([sv("1fr"), sv("2fr")]),
      "gap": v(8),
      "align": sv("center"),
    }),
  ])
  guard s.node("n1") is Some(grid)
  inspect(
    grid.container_style(),
    content="display:grid;grid-template-columns:1fr 2fr;justify-items:flex-start;align-items:center;gap:8px",
  )
}

///|
/// Cell placement is empty when a node occupies one auto-placed cell, which is
/// almost always — so almost every node renders no cell style at all.
test "cell placement is written only when it says something" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n0", index=-1, kind=Slot, props={
      "colSpan": v(2),
      "rowStart": v(3),
    }),
  ])
  guard s.node("n1") is Some(plain)
  guard s.node("n2") is Some(placed)
  inspect(plain.cell_style(), content="")
  inspect(
    placed.cell_style(),
    content=(
      #|grid-column-end:span 2;grid-row-start:3
    ),
  )
}

///|
test "a span below one is refused rather than collapsing a cell" {
  let s = Surface::new("main")
  let s = ok(s, [AddNode(parent="n0", index=-1, kind=Slot, props=Map([]))])
  debug_inspect(
    failed(s, [SetProps(id="n1", props={ "colSpan": v(0) })]),
    content=(
      #|["0 /nodes/n1/props/colSpan: expected a span of at least 1, got 0"]
    ),
  )
}

// --- the tree invariant ----------------------------------------------------

///|
test "only a slot holds a component" {
  let s = Surface::new("main")
  let s = ok(s, [AddNode(parent="n0", index=-1, kind=Slot, props=Map([]))])
  let b : Binding = {
    module_: "counterlib",
    name: "Counter",
    init: "",
    args: { "count": v(3) },
  }
  let s2 = ok(s, [BindInstance(id="n1", binding=Some(b))])
  debug_inspect(
    s2.bindings().map(p => "\{p.0} -> \{p.1.module_}/\{p.1.name}"),
    content="[\"n1 -> counterlib/Counter\"]",
  )
  debug_inspect(
    failed(s, [BindInstance(id="n0", binding=Some(b))]),
    content=(
      #|["0 /nodes/n0: only a slot holds a component; this is a stack"]
    ),
  )
  // and unbinding is how an editor empties a placeholder without removing it
  let s3 = ok(s2, [BindInstance(id="n1", binding=None)])
  debug_inspect(s3.bindings().length(), content="0")
}

///|
test "a slot holds no children and a box holds one" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n0", index=-1, kind=Box, props=Map([])),
    AddNode(parent="n2", index=-1, kind=Slot, props=Map([])),
  ])
  debug_inspect(
    failed(s, [AddNode(parent="n1", index=-1, kind=Slot, props=Map([]))]),
    content=(
      #|["0 /nodes/n1: a slot holds a component, not children"]
    ),
  )
  debug_inspect(
    failed(s, [AddNode(parent="n2", index=-1, kind=Slot, props=Map([]))]),
    content=(
      #|["0 /nodes/n2: a box holds one child, and already has one"]
    ),
  )
}

///|
/// An unreachable node is a leak a serializer would faithfully preserve, so
/// removing a node takes its whole subtree with it.
test "removing a node removes its subtree" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Stack, props=Map([])),
    AddNode(parent="n1", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n1", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
  ])
  debug_inspect(s.walk(), content="[\"n0\", \"n1\", \"n2\", \"n3\", \"n4\"]")
  let s = ok(s, [RemoveNode(id="n1")])
  debug_inspect(s.walk(), content="[\"n0\", \"n4\"]")
  // gone from the table, not merely detached
  assert_true(s.node("n2") is None)
}

///|
test "the root cannot be removed or moved" {
  let s = Surface::new("main")
  debug_inspect(
    failed(s, [RemoveNode(id="n0")]),
    content=(
      #|["0 /nodes/n0: the root cannot be removed; empty it instead"]
    ),
  )
  debug_inspect(
    failed(s, [MoveNode(id="n0", parent="n0", index=0)]),
    content=(
      #|["0 /nodes/n0: the root has no parent to move to"]
    ),
  )
}

///|
/// A cycle is a tree that walks forever rather than a layout anyone wanted.
test "a node cannot be moved into its own subtree" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Stack, props=Map([])),
    AddNode(parent="n1", index=-1, kind=Stack, props=Map([])),
  ])
  debug_inspect(
    failed(s, [MoveNode(id="n1", parent="n2", index=0)]),
    content=(
      #|["0 /nodes/n1: cannot move a node into its own subtree"]
    ),
  )
  // ...but moving it sideways is fine
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Stack, props=Map([])),
    MoveNode(id="n1", parent="n3", index=0),
  ])
  guard s.node("n0") is Some(root)
  debug_inspect(root.children, content="[\"n3\"]")
  debug_inspect(s.walk(), content="[\"n0\", \"n3\", \"n1\", \"n2\"]")
}

///|
/// A caller that got half a layout cannot tell what it now has, so it cannot
/// decide what to do next — and for a language model that means the next call
/// is a guess.
test "a batch is atomic: one bad op changes nothing" {
  let s = Surface::new("main")
  let s = ok(s, [AddNode(parent="n0", index=-1, kind=Slot, props=Map([]))])
  let before = s.to_json().stringify()
  let errors = failed(s, [
    SetProps(id="n0", props={ "gap": v(8) }),
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    SetProps(id="nope", props={ "gap": v(1) }),
  ])
  debug_inspect(
    errors,
    content=(
      #|["2 /nodes/nope: no such node: nope"]
    ),
  )
  // the two good ops before it left no trace
  inspect(s.to_json().stringify(), content=before)
}

// --- the data model --------------------------------------------------------

///|
/// `SetData("/user/name", …)` on an empty model should work: making a caller
/// create the object first is two round trips for one intent, and the first is
/// pure ceremony.
test "SetData writes by pointer, creating what it needs" {
  let s = Surface::new("main")
  let s = ok(s, [
    SetData(pointer="/user/name", value=sv("Ana")),
    SetData(pointer="/user/age", value=v(7)),
    SetData(pointer="/ready", value=Bool(true)),
  ])
  inspect(
    s.data.to_json().stringify(),
    content=(
      #|{"user":{"name":"Ana","age":7},"ready":true}
    ),
  )
}

///|
test "a malformed pointer is refused" {
  let s = Surface::new("main")
  debug_inspect(
    failed(s, [SetData(pointer="user/name", value=sv("x"))]),
    content=(
      #|["0 /data: not a JSON Pointer: user/name (it must be \"\" or start with /)"]
    ),
  )
}

///|
/// A pointer says what shape the caller wants; refusing because the slot
/// currently holds a number would make the model's history constrain its
/// future.
test "writing through a scalar replaces it" {
  let s = Surface::new("main")
  let s = ok(s, [SetData(pointer="/a", value=v(1))])
  let s = ok(s, [SetData(pointer="/a/b", value=sv("deep"))])
  inspect(
    s.data.to_json().stringify(),
    content=(
      #|{"a":{"b":"deep"}}
    ),
  )
}

// --- the document ----------------------------------------------------------

///|
/// A surface of forty nodes is mostly defaults, and a document that spells
/// them all out is one nobody can read and a model wastes its context on.
test "the document writes only what is not the default" {
  let s = Surface::new("main")
  let s = ok(s, [
    SetProps(id="n0", props={ "direction": sv("row"), "gap": v(12) }),
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
  ])
  inspect(
    s.to_json().stringify(),
    content=(
      #|{"id":"main","root":"n0","nodes":[{"id":"n0","kind":"stack","props":{"direction":"row","gap":12},"children":["n1"]},{"id":"n1","kind":"slot"}],"data":{}}
    ),
  )
}

///|
/// The same document is what a person exports, what a model reads back, and
/// what a session resumes from — so it has to survive the trip unchanged.
test "a surface round-trips through its document" {
  let s = Surface::new("main")
  let s = ok(s, [
    SetProps(id="n0", props={ "direction": sv("row"), "gap": v(6) }),
    AddNode(parent="n0", index=-1, kind=Grid, props={
      "columns": List([sv("1fr"), sv("2fr")]),
      "align": sv("center"),
      "padding": v(4),
    }),
    AddNode(parent="n1", index=-1, kind=Slot, props={ "colSpan": v(2) }),
    BindInstance(
      id="n2",
      binding=Some({
        module_: "counterlib",
        name: "Counter",
        init: "at-three",
        args: { "count": v(3) },
      }),
    ),
    SetData(pointer="/title", value=sv("Dashboard")),
  ])
  let doc = s.to_json()
  guard Surface::from_json(doc) is Some(back)
  inspect(back.to_json().stringify(), content=doc.stringify())
  assert_eq(back, s)
}

///|
/// A reopened surface must not mint an id it is already holding.
test "the id counter resumes past what the document used" {
  let s = Surface::new("main")
  let s = ok(s, [
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
  ])
  guard Surface::from_json(s.to_json()) is Some(back)
  let grown = ok(back, [
    AddNode(parent="n0", index=-1, kind=Slot, props=Map([])),
  ])
  debug_inspect(grown.walk(), content="[\"n0\", \"n1\", \"n2\", \"n3\"]")
}

///|
/// Tolerant of what it does not understand, strict about what it must: a newer
/// version's prop is dropped with the node kept, but a tree nothing can walk
/// is refused.
test "an unknown prop degrades; a broken tree is refused" {
  let doc_src =
    #|{"id": "s", "root": "n0", "nodes": [
    #|  {"id": "n0", "kind": "stack", "props": {"gap": 4, "hyperflex": "yes"}}
    #|], "data": {}}
  let doc = @json.parse(doc_src)
  guard Surface::from_json(doc) is Some(s)
  guard s.node("n0") is Some(root)
  debug_inspect(root.props.gap, content="4")
  // a child that does not exist
  let broken_src =
    #|{"id": "s", "root": "n0", "nodes": [
    #|  {"id": "n0", "kind": "stack", "children": ["ghost"]}
    #|], "data": {}}
  let broken = @json.parse(broken_src)
  assert_true(Surface::from_json(broken) is None)
  // a root that does not exist
  let rootless_src =
    #|{"id": "s", "root": "n9", "nodes": [{"id": "n0", "kind": "stack"}], "data": {}}
  let rootless = @json.parse(rootless_src)
  assert_true(Surface::from_json(rootless) is None)
}

///|
/// A document a caller supplied can say anything, including that a node is its
/// own ancestor. `walk` is depth-guarded so the tree it produces is finite even
/// when the document's is not.
test "a cyclic document walks to a bounded depth rather than forever" {
  let doc_src =
    #|{"id": "s", "root": "n0", "nodes": [
    #|  {"id": "n0", "kind": "stack", "children": ["n1"]},
    #|  {"id": "n1", "kind": "stack", "children": ["n0"]}
    #|], "data": {}}
  let doc = @json.parse(doc_src)
  guard Surface::from_json(doc) is Some(s)
  let walked = s.walk()
  assert_true(walked.length() <= 66)
  debug_inspect(walked[0], content="\"n0\"")
  debug_inspect(walked[1], content="\"n1\"")
}
