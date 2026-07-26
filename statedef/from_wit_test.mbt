// The subset gate's contract: one accepting case per row of the type table,
// one rejecting case per construct the subset excludes.
//
// The rejections matter as much as the acceptances. A subset whose boundary
// is untested drifts into "whatever the parser happened to allow", and the
// error text IS the feature — it is the only place a user learns why a
// perfectly good piece of WIT is not component state.

///|
/// Parse a block that is expected to hold exactly one component.
fn one(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// The message of the error a block raises, or "" when it does not raise.
fn err_of(src : String) -> String {
  try {
    @statedef.parse_state(src) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "scalars, lists and options map onto the FieldKind lattice" {
  let d = one(
    (
      #|interface counter {
      #|  record state {
      #|    label: string,
      #|    count: s32,
      #|    ratio: f64,
      #|    ok: bool,
      #|    small: u8,
      #|    history: list<s32>,
      #|    pick: option<string>,
      #|    pair: tuple<string, s32>,
      #|  }
      #|}
    ),
  )
  assert_eq(d.component, "Counter")
  assert_eq(d.fields.length(), 8)
  let kinds = d.fields.map(f => "\{f.name}:\{f.ty.field_kind_src()}")
  assert_eq(kinds[0], "label:@component.FText")
  assert_eq(kinds[1], "count:@component.FInt")
  assert_eq(kinds[2], "ratio:@component.FFloat")
  assert_eq(kinds[3], "ok:@component.FBool")
  assert_eq(kinds[4], "small:@component.FInt")
  assert_eq(kinds[5], "history:@component.FList")
  assert_eq(kinds[6], "pick:@component.FAny")
  assert_eq(kinds[7], "pair:@component.FList")
  // Width survives even though every integer emits a MoonBit Int, because
  // decode range-checks against it.
  assert_eq(d.fields[4].ty, TInt(width=8, signed=false))
  assert_eq(d.moonbit_ty(d.fields[4].ty), "Int")
  assert_eq(d.moonbit_ty(d.fields[5].ty), "Array[Int]")
  assert_eq(d.moonbit_ty(d.fields[6].ty), "String?")
  assert_eq(d.zero_expr(d.fields[7].ty), "(\"\", 0)")
}

///|
test "flags is a closed set, the text-set marker an open one" {
  let d = one(
    (
      #|interface todo {
      #|  flags visibility { done, active }
      #|  record state { vis: visibility, tags: text-set }
      #|}
    ),
  )
  assert_eq(d.fields[0].ty.field_kind_src(), "@component.FSet")
  assert_eq(d.fields[1].ty.field_kind_src(), "@component.FSet")
  assert_eq(d.fields[0].ty, TFlags("visibility"))
  assert_eq(d.fields[1].ty, TSet)
  // Both iterate their members, which are text either way.
  assert_eq(d.fields[0].ty.elem(), Some(TText))
  assert_eq(d.fields[1].ty.elem(), Some(TText))
}

///|
test "markers cover the kinds WIT cannot spell" {
  let d = one(
    (
      #|interface board {
      #|  record state {
      #|    detail: any,
      #|    items: values,
      #|    order: value-omap,
      #|    labels: text-omap,
      #|    slot: component,
      #|  }
      #|}
    ),
  )
  assert_eq(d.fields[0].ty, TAny)
  assert_eq(d.fields[1].ty, TList(TAny))
  assert_eq(d.fields[2].ty, TOMap(TAny))
  assert_eq(d.fields[3].ty, TOMap(TText))
  assert_eq(d.fields[4].ty, TComp(None))
  assert_eq(d.fields[2].ty.field_kind_src(), "@component.FOMap")
  // FComp carries the component it slots, so it cannot be written bare —
  // the untyped `component` marker slots one the schema does not name.
  assert_eq(
    d.fields[4].ty.field_kind_src(),
    "@component.FComp(comp=\"\", args=Map([]))",
  )
  assert_eq(d.moonbit_ty(d.fields[1].ty), "Array[@tutuca.Value]")
  assert_eq(d.moonbit_ty(d.fields[3].ty), "Map[String, String]")
}

///|
test "a sibling interface names a child-component slot" {
  let defs = @statedef.parse_state(
    (
      #|interface todo-item {
      #|  record state { title: string, done: bool }
      #|}
      #|interface todo-list {
      #|  record state { current: todo-item, rest: list<todo-item> }
      #|}
    ),
  )
  assert_eq(defs.length(), 2)
  assert_eq(defs[0].component, "TodoItem")
  assert_eq(defs[1].component, "TodoList")
  // Forward AND backward references both resolve: the component names are
  // collected in a pass of their own before any field is typed.
  assert_eq(defs[1].fields[0].ty, TComp(Some("TodoItem")))
  assert_eq(defs[1].fields[1].ty, TList(TComp(Some("TodoItem"))))
}

///|
test "records, enums and variants become named MoonBit types" {
  let d = one(
    (
      #|interface editor {
      #|  enum mode { view, edit }
      #|  record item { title: string, n: s32 }
      #|  variant sel { none, one(s32), span(tuple<s32, s32>) }
      #|  record state { m: mode, items: list<item>, s: sel }
      #|}
    ),
  )
  assert_eq(d.types.length(), 3)
  // Sorted by WIT name, so the generated module does not churn between runs.
  assert_eq(d.types.map(t => t.wit_name), ["item", "mode", "sel"])
  assert_eq(d.types.map(t => t.name), ["EditorItem", "EditorMode", "EditorSel"])
  assert_eq(d.moonbit_ty(d.fields[0].ty), "EditorMode")
  assert_eq(d.moonbit_ty(d.fields[1].ty), "Array[EditorItem]")
  assert_eq(d.zero_expr(d.fields[0].ty), "EditorMode::View")
  assert_eq(d.zero_expr(d.fields[1].ty), "[]")
  // A record's zero names every field, so `init` only writes what differs.
  let item = d.user_ty("item").unwrap()
  assert_eq(d.zero_expr(TRecord("item")), "EditorItem::{ title: \"\", n: 0 }")
  assert_eq(item.name, "EditorItem")
  // A variant payload of `tuple<a, b>` is a two-argument message, because
  // dispatch arguments are a list.
  guard d.user_ty("sel").unwrap().kind is UVariant(cases)
  assert_eq(cases.map(c => c.payload.length()), [0, 1, 2])
}

///|
test "message buckets are variants, and absent buckets are empty" {
  let d = one(
    (
      #|interface chat {
      #|  variant receive { init, tick, set-all(string) }
      #|  variant bubble { changed(s32) }
      #|  record state { n: s32 }
      #|}
    ),
  )
  assert_eq(d.receive.map(m => m.name), ["init", "tick", "setAll"])
  assert_eq(d.receive.map(m => m.variant), ["Init", "Tick", "SetAll"])
  assert_eq(d.bubble.map(m => m.name), ["changed"])
  // Not declared: most components raise no responses of their own.
  assert_eq(d.response.length(), 0)
}

///|
test "an alias is transparent, so it can name a marker" {
  let d = one(
    (
      #|interface tagger {
      #|  /// tutuca: an ordered map of counts
      #|  type tag-counts = value-omap;
      #|  type nick = string;
      #|  record state { counts: tag-counts, who: nick }
      #|}
    ),
  )
  // Resolved THROUGH the alias: the field carries the marker's type, not a
  // nominal type of its own.
  assert_eq(d.fields[0].ty, TOMap(TAny))
  assert_eq(d.fields[1].ty, TText)
}

///|
test "kebab-case becomes lowerCamel, and keywords escape the binding only" {
  let d = one(
    (
      #|interface form {
      #|  record state { first-name: string, is-open: bool, %type: string }
      #|}
    ),
  )
  assert_eq(d.fields.map(f => f.name), ["firstName", "isOpen", "type"])
  // The runtime name keeps `type` — it is what the view writes and what the
  // JSON carries; only the MoonBit binding escapes.
  assert_eq(d.fields[2].name, "type")
  assert_eq(d.fields[2].binding, "type_")
  assert_eq(d.fields[0].binding, "firstName")
}

///|
test "the reads a view makes are answerable from the schema" {
  let d = one(
    (
      #|interface board {
      #|  record card { title: string, done: bool }
      #|  record state { cards: list<card>, note: string }
      #|}
    ),
  )
  // The unknown-.field diagnostic.
  assert_eq(d.field("cards") is Some(_), true)
  assert_eq(d.field("cardz") is Some(_), false)
  // The @each diagnostic: a list is iterable, a string is not.
  assert_eq(d.fields[0].ty.elem(), Some(TRecord("card")))
  assert_eq(d.fields[1].ty.elem(), None)
  // ...and the loop body's reads are answerable too, which is the whole
  // point: today they are not collected at all.
  assert_eq(d.field_of(TRecord("card"), "title"), Some(TText))
  assert_eq(d.field_of(TRecord("card"), "titel"), None)
  // The boolean-position diagnostic.
  assert_eq(d.field_of(TRecord("card"), "done").unwrap().is_boolish(), true)
  assert_eq(d.fields[0].ty.is_boolish(), false)
  // The <x render> diagnostic.
  let slot : @statedef.StateTy = TComp(Some("Card"))
  let text : @statedef.StateTy = TText
  assert_eq(slot.is_renderable(), true)
  assert_eq(text.is_renderable(), false)
}

///|
test "out-of-subset WIT is rejected, and the message says why" {
  // Each of these is valid WIT that cannot be component state.
  let big = err_of("interface c { record state { n: s64 } }")
  assert_eq(big.contains("s64/u64"), true)
  assert_eq(big.contains("2^53"), true)
  assert_eq(
    err_of("interface c { record state { r: result<s32, string> } }").contains(
      "`result`",
    ),
    true,
  )
  assert_eq(
    err_of("interface c { record state { f: future<s32> } }").contains("future"),
    true,
  )
  assert_eq(
    err_of("interface c { record state { s: stream<s32> } }").contains("stream"),
    true,
  )
  // A plain `func` is IN the subset now — it declares a `$`-callable. A
  // method on a resource is not: there is no resource to hang it on.
  assert_eq(
    err_of("interface c { resource r { m: func(); } record state { n: s32 } }").contains(
      "resource",
    ),
    true,
  )
  assert_eq(
    err_of("interface c { resource handle; record state { n: s32 } }").contains(
      "resource",
    ),
    true,
  )
  // `map` IS standard WIT, but mizchi/wit@0.3.1 does not parse it, so it
  // surfaces as a syntax error rather than a subset rejection. Recorded here
  // so the day the parser gains it, this test fails and says so.
  assert_eq(
    err_of("interface c { record state { m: map<string, s32> } }").contains(
      "state block:",
    ),
    true,
  )
}

///|
test "a block that is not component-shaped is rejected" {
  assert_eq(
    err_of("interface c { record notstate { n: s32 } }").contains(
      "declares no `record state`",
    ),
    true,
  )
  assert_eq(
    err_of("interface c { enum state { a, b } }").contains("is not a record"),
    true,
  )
  assert_eq(
    err_of("interface c { record state { x: nope } }").contains(
      "unknown type `nope`",
    ),
    true,
  )
  // The unknown-type message lists the marker vocabulary, so the fix is in
  // the error rather than in the docs.
  assert_eq(
    err_of("interface c { record state { x: nope } }").contains("text-set"),
    true,
  )
  assert_eq(
    err_of("world w { }\ninterface c { record state { n: s32 } }").contains(
      "not component state",
    ),
    true,
  )
  assert_eq(
    err_of("package a:b;\ninterface c { record state { n: s32 } }").contains(
      "the module supplies the package",
    ),
    true,
  )
  assert_eq(
    err_of("interface c { type any = string; record state { n: s32 } }").contains(
      "reserved marker name",
    ),
    true,
  )
}

///|
test "names that collapse onto one identifier are refused" {
  // `first-name` and `firstName` both map to `firstName`; emitting one field
  // and silently dropping the other is exactly the bug the check prevents.
  let msg = err_of(
    "interface c { record state { first-name: string, firstName: bool } }",
  )
  assert_eq(msg.contains("both map to"), true)
  assert_eq(msg.contains("firstName"), true)
}

///|
test "a syntax error's offset indexes the block, not the prepended header" {
  try
    @statedef.parse_state("interface c { record state { n: %%% } }") |> ignore
  catch {
    WitSyntax(offset~, ..) => {
      // Inside the block, and past the `record state {` that precedes it.
      assert_eq(offset > 0, true)
      assert_eq(offset < 40, true)
    }
    e => fail("expected a syntax error, got \{e}")
  } noraise {
    _ => fail("expected a syntax error")
  }
}

///|
/// A `func` declares a `$`-callable: the method a PARENT calls on this
/// component, which no view of the component itself names and which therefore
/// has nowhere else to be declared.
test "a func declares a method, with its signature resolved" {
  let defs = @statedef.parse_state(
    (
      #|interface entry {
      #|  record state { title: string }
      #|  contains-text: func(q: string) -> bool;
      #|  summary: func();
      #|}
    ),
  )
  assert_eq(defs.length(), 1)
  let ms = defs[0].methods
  assert_eq(ms.map(m => m.name), ["containsText", "summary"])
  assert_eq(ms[0].wit_name, "contains-text")
  assert_eq(ms[0].params, [TText])
  assert_eq(ms[0].result, Some(TBool))
  // no result and no params is the other end of the shape
  assert_eq(ms[1].params, [])
  assert_eq(ms[1].result, None)
}

///|
/// The params and result go through the same type gate as a state field, so a
/// `func` cannot smuggle in a shape the value world has no reading of.
test "a func signature is held to the state type subset" {
  assert_eq(
    err_of("interface c { f: func(n: s64); record state { n: s32 } }").contains(
      "s64/u64",
    ),
    true,
  )
}
