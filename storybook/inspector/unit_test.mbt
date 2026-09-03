// Unit tests over the from-data builders. Built instances are read back
// through the Obj
// trait (`member`), and methods are called through the same trait (they
// surface as self-pre-bound Fns; element 0 is the this-slot).

///|
fn oget(v : @tutuca.Value, name : String) -> @tutuca.Value {
  match v {
    Obj(o) => o.field(name).unwrap_or(Null)
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
  // `Receive`, because that is what a view raises now. This helper stands in
  // for a click, and a click is an addressed message.
  guard o.handler(Receive, name) is Some(Handler(f)) else { return Null }
  match f([], @tutuca.NullCtx::{ }) {
    Some(node) => node
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
/// An Obj that declares nothing — the only shape left that the inspector
/// cannot open. It stands for a guest instance, whose fields genuinely do not
/// cross the boundary.
priv struct Undescribed {}

///|
impl @tutuca.Obj for Undescribed with fn debug(_self) {
  "Undescribed{}"
}

///|
/// An instance shows its DECLARED fields, under its own name.
test "classify: a described instance opens into its fields" {
  let insp = @inspector.Inspector::new()
  let card = sample_comp().make({ "title": Str("Hello") })
  let obj = insp.classify(card)
  inspect(otext(obj, "typeText"), content="RichSample")
  let rows = olist(obj, "items")
  assert_true(rows.length() > 0)
  assert_true(oget(rows[0], "key") is Str("title"))
  // ...and the field's VALUE is classified too, not stringified
  inspect(otext(oget(rows[0], "child"), "text"), content="\"Hello\"")
}

///|
/// The name survives NESTING — the case that actually showed up, in a
/// storybook Instance tab over a JSON editor: a component holding a list of
/// child components rendered them as `Object {1}`, because only the root row
/// went through `instance_snapshot` and every level below it through
/// `classify`.
test "classify: a nested instance keeps its name" {
  let insp = @inspector.Inspector::new()
  let card = sample_comp().make({ "title": Str("Hello") })
  let arr = insp.classify(List([card]))
  inspect(otext(arr, "typeText"), content="Array")
  let child = oget(olist(arr, "items")[0], "child")
  inspect(otext(child, "typeText"), content="RichSample")
}

///|
/// The fallback survives for the one case that still needs it.
test "classify: an instance that declares nothing is still an opaque leaf" {
  let insp = @inspector.Inspector::new()
  let leaf = insp.classify(Obj(Undescribed::{ }))
  assert_true(oget(leaf, "text") is Str(s) && s.contains("Undescribed"))
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
}

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
    initial=RichState::{ title: "", count: 0, tags: [], open: false, },
    compute={
      "label": (s : RichState, _args, _stack) => Str(s.title),
      "double": (s : RichState, _args, _stack) => Num((s.count * 2).to_double()),
    },
    update=(s : RichState, msg, _ctx) => {
      match msg {
        Receive("inc", _) => Next({ ..s, count: s.count + 1, })
        Receive("reset", _) => Next({ ..s, count: 0, })
        Receive("ping", _) | Intent("onChild", _) | Receive("onData", _) =>
          Next(s)
        _ => Unhandled
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
  // The author's own spelling, not a label reconstructed from the runtime
  // kind — which is the whole difference between describing and reflecting.
  assert_true(f0.get("type") is Some(Str("String")))
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
  // `update` is one opaque pattern match at run time, so reflection could
  // only ever say THAT it exists. The schema names what it answers.
  assert_true(d.get("viewHandlers") is Some(List([Str("inc"), Str("reset")])))
  // `onData` is an ANSWER, and an answer is an ordinary message — so it sits
  // beside `ping` rather than in a bucket of its own.
  assert_true(d.get("receive") is Some(List([Str("ping"), Str("onData")])))
  assert_true(d.get("intent") is Some(List([Str("onChild")])))
  assert_true(d.get("bubble") is None)
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
  // One section per NON-EMPTY group, which is why there is no row for a
  // bucket this component does not use.
  assert_true(
    labels ==
    [
      Str("Fields"),
      Str("Methods"),
      Str("View handlers"),
      Str("Receive"),
      Str("Intent"),
      Str("Alter"),
      Str("Views"),
    ],
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
  // No descriptor passed: the instance names its own fields now.
  guard @inspector.instance_snapshot(card) is Map(d) else {
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
    { field: "value", key: None, },
    { field: "rows", key: Some(KInt(1)), },
    { field: "byName", key: Some(KStr("a")), },
  ]
  inspect(@inspector.path_keys_label(keys), content="value.rows[1].byName[a]")
}

///|
test "record_to_entry maps an observer record onto an ActivityEntry" {
  let insp = @inspector.Inspector::new()
  let record : @transactor.ObserveRecord = {
    origin: View,
    bucket: Receive,
    is_answer: false,
    name: "click",
    args: [],
    path: @tutuca.Path::new(),
    path_keys: [{ field: "value", key: None, }],
    target_path: @tutuca.DispatchPath::new(),
    matched: Exact,
    before: Some(Num(1)),
    after: Some(Num(2)),
    seq: 7,
    walk: 0,
    parent_seq: 0,
  }
  let entry = insp.record_to_entry(record)
  assert_true(oget(entry, "kind") is Str("receive"))
  // The bucket's word and WHO raised it are two different answers, and the
  // row shows both: a `receive` from a view and a `receive` a handler pushed
  // read the same otherwise.
  assert_true(oget(entry, "origin") is Str("view"))
  assert_true(oget(entry, "name") is Str("click"))
  assert_true(oget(entry, "matched") is Str("exact"))
  assert_true(oget(entry, "pathLabel") is Str("value"))
  assert_true(oget(entry, "time") is Str("#7"))
  assert_true(oget(entry, "hasAfter") is Bool(true))
  assert_true(oget(entry, "before") is Obj(_))
  // the outgoing side of a request has no after
  let outgoing = insp.record_to_entry({ ..record, after: None, })
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

///|
/// A schema-backed component, described rather than reflected.
fn schema_sample_comp() -> @component.Component {
  @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Described",
    initial=DescribedState::{ title: "", count: 0, tags: [], open: false, },
    update=(_s : DescribedState, _msg, _ctx) => Unhandled,
  )
}

///|
/// What a schema buys the inspector, against what reflection can reach.
test "a described component surfaces what reflection cannot" {
  guard @inspector.component_summary(schema_sample_comp()) is Map(d) else {
    fail("summary is not a Map")
  }
  // THE one. At runtime `update` is a single opaque pattern match, so the
  // reflected summary can only report that one exists; the schema knows
  // every name it answers.
  assert_eq(d.get("viewHandlers"), Some(List([Str("inc"), Str("reset")])))
  // Buckets that are invisible without a schema — they are raised from
  // MoonBit, never written in a view.
  assert_eq(d.get("receive"), Some(List([Str("ping"), Str("onData")])))
  assert_eq(d.get("intent"), Some(List([Str("onChild")])))
  // The selectors a test addresses, and the fixtures it can seed from.
  assert_eq(d.get("ids"), Some(List([Str("counter"), Str("resetBtn")])))
  assert_eq(d.get("fixtures"), Some(List([Str("fresh")])))
  assert_eq(d.get("fingerprint"), Some(Str("deadbeefcafe0001")))
  // A field carries the WIT spelling and its element type, where the
  // reflected form could only say "list".
  guard! d.get("fields") is Some(List(fields))
  guard! fields[2] is Map(tags)
  assert_eq(tags.get("name"), Some(Str("tags")))
  assert_eq(tags.get("type"), Some(Str("Array[String]")))
  assert_eq(tags.get("elem"), Some(Str("String")))
}

///|
/// `component()` requires a schema, so `component_summary` reads one source —
/// this pins that the descriptor really is the declaration, right down to the
/// fixture's own fingerprint.
test "the summary is the declaration, not a reconstruction" {
  guard @inspector.component_summary(sample_comp()) is Map(d) else {
    fail("summary is not a Map")
  }
  assert_eq(d.get("fingerprint"), Some(Str("rich_state")))
  assert_eq(d.get("ids"), Some(List([])))
  assert_eq(d.get("fixtures"), Some(List([])))
}

///|
/// The metadata FLOOR, over a GENERATED component rather than a hand-written
/// fixture.
///
/// The two tests above pin what the summary says; this one pins that a
/// component compiled by `gen-views` still SUPPLIES it. That is the property
/// every deletion in the generator has to preserve and the one a snapshot of
/// the emitter cannot see: the inspector and the state editor are generated
/// from this descriptor rather than written per component, so a channel that
/// stops being emitted does not break a build — it silently empties a panel.
///
/// `RichSample` is the fixture that declares every channel at once. Built here
/// with no handlers at all, because what is under test is what the SCHEMA
/// supplies — `swap` and `alter` are author-wired runtime facts and are pinned
/// by the tests above.
test "a generated component fills every summary row its schema can" {
  guard @inspector.component_summary(@inspector.rich_sample_component())
    is Map(d) else {
    fail("summary is not a Map")
  }
  // Every row exists, whether or not this component fills it.
  for
    row in [
      "name", "id", "fingerprint", "fields", "methods", "viewHandlers", "receive",
      "intent", "alter", "ids", "fixtures", "views",
    ] {
    assert_true(d.get(row) is Some(_))
  }
  // ...and every row RichSample declares is actually populated.
  assert_eq(d.get("name"), Some(Str("RichSample")))
  assert_eq(d.get("viewHandlers"), Some(List([Str("inc"), Str("reset")])))
  // `onData` is an ANSWER and lands beside `ping`; `onChild` is ROUTED and has
  // a bucket of its own.
  assert_eq(d.get("receive"), Some(List([Str("ping"), Str("onData")])))
  assert_eq(d.get("intent"), Some(List([Str("onChild")])))
  assert_eq(d.get("methods"), Some(List([Str("double"), Str("label")])))
  // A fingerprint is computed, not merely present: 64 bits of hex.
  guard! d.get("fingerprint") is Some(Str(fp))
  assert_eq(fp.length(), 16)
  // Each field row carries the name and the WIT spelling the author wrote —
  // what the state editor labels a control with and picks a control from.
  guard! d.get("fields") is Some(List(fields))
  assert_eq(fields.length(), 4)
  for f in fields {
    guard! f is Map(row)
    assert_true(row.get("name") is Some(Str(_)))
    assert_true(row.get("type") is Some(Str(_)))
  }
  // The views the component can be rendered under are reachable too.
  guard! d.get("views") is Some(List(views))
  assert_eq(views.length(), 2)
}

///|
impl @component.Fields for RichState with fn encode(s) {
  {
    "title": Str(s.title),
    "count": Num(s.count.to_double()),
    "tags": (List(s.tags) : @tutuca.Value),
    "open": Bool(s.open),
  }
}

///|
impl @component.Fields for RichState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  guard f.get("count") is Some(Num(n_count)) else { return None }
  let v_count = n_count.to_int()
  guard f.get("tags") is Some(List(v_tags)) else { return None }
  guard f.get("open") is Some(Bool(v_open)) else { return None }
  Some({ title: v_title, count: v_count, tags: v_tags, open: v_open, })
}

///|
/// Hand-written and COMPLETE: this fixture exists to make every panel of the
/// component inspector have something to show, so it declares one of
/// everything.
impl @component.Fields for RichState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="rich_state",
    fields=[
      @component.FieldInfo::new("title", TyText),
      @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("tags", TyList(TyAny)),
      @component.FieldInfo::new("open", TyBool),
    ],
    view_handlers=["inc", "reset"],
    // `onData` is an ANSWER, and an answer is an ordinary message in v2 — so
    // it is declared beside `ping` rather than in a bucket of its own.
    receives=["ping", "onData"],
    intents=["onChild"],
    methods=["double", "label"],
    view_names=["main", "compact"],
  )
}

///|
/// The `Described` fixture's own state.
///
/// A schema belongs to the type that has the fields, so a second description
/// needs a second type.
priv struct DescribedState {
  title : String
  count : Int
  tags : Array[@tutuca.Value]
  open : Bool
}

///|
impl @component.Fields for DescribedState with fn encode(s) {
  {
    "title": Str(s.title),
    "count": Num(s.count.to_double()),
    "tags": (List(s.tags) : @tutuca.Value),
    "open": Bool(s.open),
  }
}

///|
impl @component.Fields for DescribedState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  guard f.get("count") is Some(Num(n_count)) else { return None }
  guard f.get("tags") is Some(List(v_tags)) else { return None }
  guard f.get("open") is Some(Bool(v_open)) else { return None }
  Some({ title: v_title, count: n_count.to_int(), tags: v_tags, open: v_open, })
}

///|
impl @component.Fields for DescribedState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="deadbeefcafe0001",
    fields=[
      @component.FieldInfo::new("title", TyText),
      @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("tags", TyList(TyText)),
    ],
    view_handlers=["inc", "reset"],
    // `onData` is an ANSWER, and an answer is an ordinary message in v2 — so
    // it is declared beside `ping` rather than in a bucket of its own.
    receives=["ping", "onData"],
    intents=["onChild"],
    methods=["label"],
    ids=["counter", "resetBtn"],
    view_names=["main"],
    init_names=["fresh"],
  )
}

// ---------------------------------------------------------------------------
// The schema-driven state editor
// ---------------------------------------------------------------------------

///|
/// A form over a component nobody wrote a form for.
///
/// One row per DECLARED field, each carrying the WIT spelling and a control
/// picked from the kind — which is the whole point: none of it is written per
/// component, and none of it was reachable before an instance could say what
/// fields it has.
test "state editor: rows come from the schema, controls from the kinds" {
  let insp = @inspector.Inspector::new()
  let card = sample_comp().make({
    "title": Str("Hello"),
    "count": Num(3),
    "tags": List([Str("a")]),
    "open": Bool(true),
  })
  let rows = insp.editor_rows(card)
  inspect(rows.length(), content="4")
  assert_true(oget(rows[0], "name") is Str("title"))
  assert_true(oget(rows[0], "kind") is Str("text"))
  assert_true(oget(rows[0], "text") is Str("Hello"))
  assert_true(oget(rows[1], "kind") is Str("num"))
  assert_true(oget(rows[1], "num") is Num(3.0))
  // the schema's own spelling, not a label reconstructed from the runtime
  // kind. The spelling is a function of the type, so it normalizes the way the
  // generator already did.
  assert_true(oget(rows[2], "type") is Str("Array[Any]"))
  // a list is a tree, not a control: shown, not edited
  assert_true(oget(rows[2], "kind") is Str("readonly"))
  assert_true(oget(rows[2], "editable") is Bool(false))
  assert_true(oget(rows[3], "kind") is Str("bool"))
  assert_true(oget(rows[3], "flag") is Bool(true))
  // an instance that declares nothing has no form to draw
  assert_eq(insp.editor_rows(Obj(Undescribed::{ })).length(), 0)
}

///|
/// The editor names the component and holds the instance it edits.
test "state editor: the form wraps the target it edits" {
  let insp = @inspector.Inspector::new()
  let card = sample_comp().make({ "title": Str("Hi") })
  let ed = insp.edit_instance(card)
  assert_true(oget(ed, "name") is Str("RichSample"))
  assert_true(oget(ed, "target") is Obj(_))
  assert_eq(olist(ed, "rows").length(), 4)
}

///|
/// The state editor reaches a generated mutator BY NAME through `Obj::member`
/// — it holds a bare `Value`, so it has no other way in. That means two places
/// have to agree on how a field name becomes a mutator name, and neither can
/// see the other: `component()` builds `setTitle`, the editor asks for it.
///
/// They agree because there is one function, not two spellings of a convention.
test "the editor's setter name is the one the component generated" {
  let card = sample_comp().make({ "title": Str("Hello") })
  guard! card is Obj(o)
  // The name the convention produces...
  let setter = @tutuca.mutator_name("set", "title")
  assert_eq(setter, "setTitle")
  // ...is a mutator the instance actually answers to.
  guard! o.field(setter) is Some(Fn(set))
  guard! set([Null, Str("Bye")]) is Obj(o2)
  assert_eq(o2.field("title"), Some(Str("Bye")))
  // An empty field name has no mutator to build, and must not produce a bare
  // verb that collides with something else.
  assert_eq(@tutuca.mutator_name("set", ""), "set")
}
