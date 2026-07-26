// Unit tests over the from-data builders — the port of the pure assertions
// in the JS *.dev.js getTests. Built instances are read back through the Obj
// trait (`obj_field`), and methods are called through the same trait (they
// surface as self-pre-bound Fns; element 0 is the this-slot).

///|
fn oget(v : @tutuca.Value, name : String) -> @tutuca.Value {
  match v {
    Obj(o) => o.obj_field(name).unwrap_or(Null)
    _ => Null
  }
}

///|
fn ocall(v : @tutuca.Value, name : String) -> @tutuca.Value {
  match oget(v, name) {
    Fn(f) => f([Null])
    _ => Null
  }
}

///|
/// Dispatch an Input to a component instance and return the successor.
///
/// Paging moved from a `mutate` bucket to an `update` arm, so `prevPage` /
/// `nextPage` answer a DISPATCH now rather than a field read — `ocall` would
/// find no Fn to call. This is how the view reaches them too.
fn odispatch(v : @tutuca.Value, name : String) -> @tutuca.Value {
  guard v is Obj(o) else { return Null }
  guard o.obj_handler(Input, name) is Some(Handler(f)) else { return Null }
  match f([], @tutuca.NullCtx::{  }) {
    Some(node) => node.as_value().unwrap_or(Null)
    None => v
  }
}

///|
fn otext(v : @tutuca.Value, name : String) -> String {
  match ocall(v, name) {
    Str(s) => s
    other => other.to_display_string()
  }
}

///|
fn olist(v : @tutuca.Value, name : String) -> Array[@tutuca.Value] {
  match oget(v, name) {
    List(a) => a
    _ => []
  }
}

///|
fn long_list_value(n : Int) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  for i in 1..<=n {
    items.push(Num(i.to_double()))
  }
  List(items)
}

///|
test "classify: leaves render the JS leaf texts" {
  let insp = @inspector.Inspector::new()
  inspect(
    otext(insp.classify(Str("hi")), "text"),
    content=(
      #|"hi"
    ),
  )
  inspect(otext(insp.classify(Num(42)), "text"), content="42")
  let t = insp.classify(Bool(true))
  inspect(otext(t, "text"), content="true")
  assert_true(otext(t, "cssClass").contains("text-success"))
  let f = insp.classify(Bool(false))
  inspect(otext(f, "text"), content="false")
  assert_true(otext(f, "cssClass").contains("text-warning"))
  assert_true(insp.classify(Fn(_a => Null)) is Obj(_))
}

///|
test "classify: composites build keyed rows and count them" {
  let insp = @inspector.Inspector::new()
  let arr = insp.classify(List([Num(1), Str("two"), Bool(true), Null]))
  inspect(otext(arr, "typeText"), content="Array")
  inspect(otext(arr, "countText"), content="(4)")
  inspect(olist(arr, "items").length(), content="4")
  // rows are JsonProperty instances keyed by index
  let first = olist(arr, "items")[0]
  assert_true(oget(first, "key") is Str("0"))
  let obj = insp.classify(Map({ "a": Num(1), "b": Num(2) }))
  inspect(otext(obj, "typeText"), content="Object")
  inspect(otext(obj, "countText"), content="{2}")
}

///|
test "classify: an instance Value without seq entries is an opaque leaf" {
  let insp = @inspector.Inspector::new()
  let card = sample_comp().make({ "title": Str("Hello") })
  let leaf = insp.classify(card)
  assert_true(oget(leaf, "text") is Str(s) && s.contains("Sample"))
}

///|
test "composite pagination: 25 items page at 10, prev/next clamp" {
  let insp = @inspector.Inspector::new()
  let arr = insp.classify(long_list_value(25))
  inspect(otext(arr, "pageIndicatorText"), content="1 / 3")
  assert_true(ocall(arr, "cannotPrevPage") is Bool(true))
  assert_true(ocall(arr, "cannotNextPage") is Bool(false))
  assert_true(ocall(arr, "hasPagination") is Null) // not a method — view uses showPagination
  let p2 = odispatch(arr, "nextPage")
  inspect(otext(p2, "pageIndicatorText"), content="2 / 3")
  let p3 = odispatch(p2, "nextPage")
  inspect(otext(p3, "pageIndicatorText"), content="3 / 3")
  assert_true(ocall(p3, "cannotNextPage") is Bool(true))
  // clamped: another next stays on the last page
  inspect(
    otext(odispatch(p3, "nextPage"), "pageIndicatorText"),
    content="3 / 3",
  )
  // and back
  inspect(
    otext(odispatch(p3, "prevPage"), "pageIndicatorText"),
    content="2 / 3",
  )
}

///|
test "deep_expand opens every level" {
  let insp = @inspector.Inspector::new()
  let v = insp.classify(Map({ "xs": List([Num(1)]) }))
  assert_true(oget(v, "isExpanded") is Bool(false))
  let open = @inspector.deep_expand(v)
  assert_true(oget(open, "isExpanded") is Bool(true))
  let inner = oget(olist(open, "items")[0], "child")
  assert_true(oget(inner, "isExpanded") is Bool(true))
}

///|
priv struct RichState {
  title : String
  count : Int
  tags : Array[@tutuca.Value]
  open : Bool
} derive(ToJson, FromJson)

///|
fn sample_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div @text=".title"></div>
        ),
      ),
      "compact": @anode.View::new(
        "compact",
        raw_view=(
          #|<span @text=".title"></span>
        ),
      ),
    },
    name="RichSample",
    init=RichState::{ title: "", count: 0, tags: [], open: false },
    compute={
      "label": (s : RichState, _args) => Str(s.title),
      "double": (s : RichState, _args) => Num((s.count * 2).to_double()),
    },
    update=(s : RichState, msg, _ctx) => {
      match msg {
        Input("inc", _) => Some({ ..s, count: s.count + 1 })
        Input("reset", _) => Some({ ..s, count: 0 })
        Receive("ping", _) | Bubble("onChild", _) | Response("onData", _) =>
          Some(s)
        _ => None
      }
    },
    loop_with={
      "rows": (_s : RichState, _seq, _ctx) => {
        @component.LoopWith::new(start=0, end=0)
      },
    },
  )
}

///|
test "component_summary reads fields, buckets, and view sources" {
  guard @inspector.component_summary(sample_comp()) is Map(d) else {
    fail("summary is not a Map")
  }
  assert_true(d.get("name") is Some(Str("RichSample")))
  guard d.get("fields") is Some(List(fields)) else { fail("no fields") }
  inspect(fields.length(), content="4")
  guard fields[0] is Map(f0) else { fail("field row is not a Map") }
  assert_true(f0.get("name") is Some(Str("title")))
  assert_true(f0.get("type") is Some(Str("text")))
  assert_true(f0.get("default") is Some(Str("")))
  // methods = the compute names. `inc`/`reset` are update arms, not
  // methods: they answer a dispatch rather than a field read. The generated
  // mutators (setTitle, toggleOpen, …) never appear either — they live in
  // their own table.
  guard d.get("methods") is Some(List(methods)) else { fail("no methods") }
  assert_true(methods.contains(Str("label")))
  assert_true(methods.contains(Str("double")))
  assert_false(methods.contains(Str("inc")))
  assert_false(methods.contains(Str("reset")))
  assert_false(methods.contains(Str("setTitle")))
  assert_false(methods.contains(Str("toggleOpen")))
  assert_false(methods.contains(Str("pushInTags")))
  // update is one opaque pattern match — surfaced as a presence flag
  assert_true(d.get("update") is Some(List([Str("update")])))
  assert_true(d.get("alter") is Some(List([Str("rows")])))
  guard d.get("views") is Some(List(views)) else { fail("no views") }
  inspect(views.length(), content="2")
  guard views[0] is Map(v0) else { fail("view row is not a Map") }
  assert_true(v0.get("name") is Some(Str("main")))
  assert_true(v0.get("rawView") is Some(Str(src)) && src.contains(".title"))
}

///|
test "inspect_component builds one section per non-empty group" {
  let insp = @inspector.Inspector::new()
  let ci = insp.inspect_component(sample_comp())
  assert_true(oget(ci, "compName") is Str("RichSample"))
  inspect(otext(ci, "idText").contains("#"), content="true")
  let labels = olist(ci, "sections").map(s => oget(s, "label"))
  assert_true(
    labels ==
    [Str("Fields"), Str("Methods"), Str("Update"), Str("Alter"), Str("Views")],
  )
  // Fields starts expanded, the rest collapsed
  let sections = olist(ci, "sections")
  assert_true(oget(sections[0], "isExpanded") is Bool(true))
  assert_true(oget(sections[1], "isExpanded") is Bool(false))
  inspect(otext(sections[0], "countText"), content="(4)")
}

///|
test "instance_snapshot + inspect_instance expose the field rows" {
  let insp = @inspector.Inspector::new()
  let comp = sample_comp()
  let card = comp.make({
    "title": Str("Hello"),
    "count": Num(3),
    "tags": List([Str("a"), Str("b")]),
    "open": Bool(true),
  })
  guard @inspector.instance_snapshot(card, comp) is Map(d) else {
    fail("snapshot is not a Map")
  }
  assert_true(d.get("name") is Some(Str("RichSample")))
  guard d.get("fields") is Some(Map(fields)) else { fail("no fields") }
  inspect(fields.length(), content="4")
  assert_true(fields.get("count") is Some(Num(3)))
  // the wrapper holds InstanceFields, expanded, typed by the component name
  let ii = insp.inspect_instance(card, comp)
  let rows = oget(ii, "value")
  inspect(otext(rows, "typeText"), content="RichSample")
  inspect(otext(rows, "countText"), content="{4}")
  assert_true(oget(rows, "isExpanded") is Bool(true))
  inspect(olist(rows, "items").length(), content="4")
}

///|
test "classify_schema dispatches on the schema's keywords" {
  let insp = @inspector.Inspector::new()
  // boolean schemas
  inspect(
    otext(insp.classify_schema(Bool(false)), "text"),
    content="no value allowed (false)",
  )
  // $ref never resolves
  let r = insp.classify_schema(Map({ "$ref": Str("#/$defs/address") }))
  assert_true(oget(r, "target") is Str("#/$defs/address"))
  // object with required properties
  let o = insp.classify_schema(
    Map({
      "type": Str("object"),
      "properties": Map({
        "id": Map({ "type": Str("integer"), "minimum": Num(1) }),
      }),
      "required": List([Str("id")]),
    }),
  )
  inspect(otext(o, "typeText"), content="object")
  inspect(otext(o, "countText"), content="{1}")
  let prop = olist(o, "items")[0]
  assert_true(oget(prop, "key") is Str("id"))
  assert_true(oget(prop, "required") is Bool(true))
  let id_node = oget(prop, "child")
  inspect(otext(id_node, "typeText"), content="integer")
  assert_true(olist(id_node, "badges").contains(Str("≥ 1")))
  // bare primitive item types inline into the array label
  let a = insp.classify_schema(
    Map({ "type": Str("array"), "items": Map({ "type": Str("string") }) }),
  )
  inspect(otext(a, "typeText"), content="array of string")
  // enum members render as values, listed one per line
  let e = insp.classify_schema(
    Map({ "enum": List([Str("admin"), Str("editor"), Str("viewer")]) }),
  )
  inspect(otext(e, "typeText"), content="enum")
  inspect(otext(e, "countText"), content="(3)")
  // combinator phrasing
  let c = insp.classify_schema(
    Map({ "anyOf": List([Map({ "type": Str("string") }), Bool(true)]) }),
  )
  inspect(otext(c, "typeText"), content="any of")
  inspect(olist(c, "items").length(), content="2")
  // multi-type
  let m = insp.classify_schema(
    Map({ "type": List([Str("string"), Str("null")]) }),
  )
  inspect(otext(m, "typeText"), content="string | null")
}

///|
test "schema_view holds both the classified tree and the raw value" {
  let insp = @inspector.Inspector::new()
  let sv = insp.schema_view(Map({ "type": Str("string") }))
  assert_true(oget(sv, "showRaw") is Bool(false))
  inspect(otext(sv, "toggleLabel"), content="raw schema")
  assert_true(oget(sv, "value") is Obj(_))
  assert_true(oget(sv, "raw") is Obj(_))
  assert_true(oget(sv, "rawSchema") is Map(_))
}

///|
test "path_keys_label joins fields and keys" {
  let keys : Array[@tutuca.StepKey] = [
    { field: "value", key: None },
    { field: "rows", key: Some(KInt(1)) },
    { field: "byName", key: Some(KStr("a")) },
  ]
  inspect(@inspector.path_keys_label(keys), content="value.rows[1].byName[a]")
}

///|
test "record_to_entry maps an observer record onto an ActivityEntry" {
  let insp = @inspector.Inspector::new()
  let record : @transactor.ObserveRecord = {
    kind: Input,
    name: "click",
    args: [],
    path: @tutuca.Path::new(),
    path_keys: [{ field: "value", key: None }],
    target_path: @tutuca.DispatchPath::new(),
    matched: Exact,
    before: Some(Num(1)),
    after: Some(Num(2)),
    seq: 7,
  }
  let entry = insp.record_to_entry(record)
  assert_true(oget(entry, "kind") is Str("input"))
  assert_true(oget(entry, "name") is Str("click"))
  assert_true(oget(entry, "matched") is Str("exact"))
  assert_true(oget(entry, "pathLabel") is Str("value"))
  assert_true(oget(entry, "time") is Str("#7"))
  assert_true(oget(entry, "hasAfter") is Bool(true))
  assert_true(oget(entry, "before") is Obj(_))
  // the outgoing side of a request has no after
  let outgoing = insp.record_to_entry({ ..record, after: None })
  assert_true(oget(outgoing, "hasAfter") is Bool(false))
  assert_true(oget(outgoing, "after") is Null)
}

///|
test "build_inspector_views resolves the descriptor through a registry" {
  let insp = @inspector.Inspector::new()
  let comp = sample_comp()
  let comps = @component.Components::new()
  comps.register(comp)
  let card = comp.make({ "title": Str("Hi") })
  let views = insp.build_inspector_views(card, comps~)
  assert_true(views.has_component)
  assert_true(oget(views.component_view, "compName") is Str("RichSample"))
  inspect(
    otext(oget(views.instance_view, "value"), "typeText"),
    content="RichSample",
  )
  // without a registry the value falls back to the data inspector
  let plain = insp.build_inspector_views(Num(3))
  assert_false(plain.has_component)
  assert_true(plain.component_view is Null)
}
