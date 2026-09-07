// Every `spec:` shape, as the definitions it reads to.
//
// This was a DIFFERENTIAL assertion: the same section read directly and
// lowered into the block language for the other front end to read, compared
// declaration by declaration. A reader that merely parses could be producing
// anything; a reader that agrees with the thing it replaces is one you can take
// the other side away from. That is what made the lowering safe to delete, and
// it went with it.
//
// `wire_value` is the case that most needed it and the one this file keeps
// closest: it is the ONE place this reader writes source rather than reading
// it — a `provide`/`lookup` value is a wire format with `@component` on the
// other side — and every shape it writes was compared against what the printer
// wrote for the same line while there was still a printer to ask.

///|
/// Both readings of one `spec:` section, as text to compare.
fn read_defs(src : String) -> String {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Spec) is Some(section) else { return "no spec section" }
  let direct = @statedef.state_of_tutu(section.decls, name="T") catch {
    e => return "ERR " + @statedef.DefError::message(e)
  }
  flat(@debug.to_string(direct))
}

///|
/// The Debug renderer wraps at a width, and a span is an offset into a file
/// whose length this test is not about. Both out, so what is snapshotted is
/// the declarations.
fn flat(s : String) -> String {
  let out = StringBuilder()
  let cs = s.to_array()
  let mut i = 0
  let mut space = false
  while i < cs.length() {
    // `span: {start: 1, end_: 9}` and `{ start: … }` alike.
    if i + 4 < cs.length() &&
      cs[i] == 's' &&
      cs[i + 1] == 'p' &&
      cs[i + 2] == 'a' &&
      cs[i + 3] == 'n' {
      out.write_string("span:_")
      while i < cs.length() && cs[i] != '}' {
        i = i + 1
      }
      i = i + 1
      continue
    }
    if cs[i] is (' ' | '\n' | '\t') {
      space = true
    } else {
      if space && !(cs[i] is (')' | ']' | '}' | ',')) {
        out.write_char(' ')
      }
      space = false
      out.write_char(cs[i])
    }
    i = i + 1
  }
  let mut text = out.to_string()
  for _ in 0..<3 {
    for
      pair in [
        (",)", ")"),
        (",]", "]"),
        (",}", "}"),
        ("( ", "("),
        ("[ ", "["),
        ("{ ", "{"),
      ] {
      text = text.replace_all(old=pair.0, new=pair.1)
    }
  }
  text
}

///|
/// One component, as the definitions it reads to.
fn agree(body : String) -> String {
  read_defs("spec:\n  T:\n" + body)
}

///|
test "a field, a property and a rule, as the definitions they read to" {
  let bodies = [
    "    field n :: Int\n", "    field s :: String\n    field xs :: List.of(String)\n",
    "    field m :: Map.of(String, Int)\n", "    field o :: maybe(Int)\n", "    field c :: Instance\n",
    "    field n :: Int\n    property double :: Int ~public\n", "    field n :: Int\n    property shown :: Int ~public:\n      get: it.n\n",
    "    field n :: Int\n    pred ok: it.n > 0\n", "    field n :: Int\n    invariant sane: it.n >= 0\n",
    "    field n :: Int\n    where it.n >= 0\n", "    field n :: Int\n    where it.n in_range(0, 100)\n",
    "    field s :: String\n    where it.s is_one_of [\"a\", \"b\"]\n", "    field s :: String\n    where it.s non_empty\n",
    "    field n :: Int\n    message bump\n    message add(Int)\n", "    field n :: Int\n    intent picked(String)\n",
    "    field n :: Int\n    express intent asked(Bool)\n",
    // The wiring sections. `wire_value` is the one place the reader WRITES
    // source, so it is the one place worth holding to the printer line by
    // line — a path, a seq-access, `self`, and each shape a default takes.
     "    field theme :: String\n    provide theme = it.theme\n", "    field items :: List.of(Any)\n    field at :: String\n    provide sel = it.items[it.at]\n",
    "    field n :: Int\n    provide Cell = self\n", "    field n :: Int\n    lookup theme\n",
    "    field n :: Int\n    lookup theme = \"plain\"\n", "    field n :: Int\n    lookup n = 0\n",
    "    field n :: Int\n    lookup on = true\n", "    field n :: Int\n    lookup v = null\n",
  ]
  let out = StringBuilder()
  for b in bodies {
    out.write_string(b.trim().to_owned() + "\n  -> " + agree(b) + "\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|field n :: Int
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field s :: String
      #|    field xs :: List.of(String)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "s", binding: "s", ty: TyText, doc: None, attrs: []}, {name: "xs", binding: "xs", ty: TyList(TyText), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field m :: Map.of(String, Int)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "m", binding: "m", ty: TyOMap(TyInt(width=32, signed=true)), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field o :: maybe(Int)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "o", binding: "o", ty: TyOption(TyInt(width=32, signed=true)), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field c :: Instance
      #|  -> [{source_name: "T", component: "T", fields: [{name: "c", binding: "c", ty: TyComp(None), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    property double :: Int ~public
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [{name: "double", ty: TyInt(width=32, signed=true), public_: true, writable: false, getter: None, setter: None, doc: None}], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    property shown :: Int ~public:
      #|      get: it.n
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [{name: "shown", ty: TyInt(width=32, signed=true), public_: true, writable: false, getter: Some(".n"), setter: None, doc: None}], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    pred ok: it.n > 0
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [{kind: RPred, name: "ok", body: EChain(family=FCompare, ops=[">"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), format: None, doc: None,span:_, name_span:_}], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    invariant sane: it.n >= 0
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [{kind: RInvariant, name: "sane", body: EChain(family=FCompare, ops=[">="], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), format: None, doc: None,span:_, name_span:_}], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    where it.n >= 0
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "n", subject_span:_, relation: DCompare(op=DGe, rhs=DLit(0)), ref_span:_}], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    where it.n in_range(0, 100)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "n", subject_span:_, relation: DBetween(lo=DLit(0), hi=DLit(100)), ref_span:_}], doc: None, category: "", keywords: []}]
      #|field s :: String
      #|    where it.s is_one_of ["a", "b"]
      #|  -> [{source_name: "T", component: "T", fields: [{name: "s", binding: "s", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "s", subject_span:_, relation: DOneOf([RStr("a"), RStr("b")]), ref_span:_}], doc: None, category: "", keywords: []}]
      #|field s :: String
      #|    where it.s non_empty
      #|  -> [{source_name: "T", component: "T", fields: [{name: "s", binding: "s", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "s", subject_span:_, relation: DNonEmpty, ref_span:_}], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    message bump
      #|    message add(Int)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [{source_name: "bump", name: "bump", variant: "Bump", payload: [], variadic: false, doc: None}, {source_name: "add", name: "add", variant: "Add", payload: [TyInt(width=32, signed=true)], variadic: false, doc: None}], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    intent picked(String)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [{source_name: "picked", name: "picked", variant: "Picked", payload: [TyText], variadic: false, doc: None}], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    express intent asked(Bool)
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [{source_name: "asked", name: "asked", variant: "Asked", payload: [TyBool], variadic: false, doc: None}], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field theme :: String
      #|    provide theme = it.theme
      #|  -> [{source_name: "T", component: "T", fields: [{name: "theme", binding: "theme", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [{name: "theme", source: ".theme",span:_}], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field items :: List.of(Any)
      #|    field at :: String
      #|    provide sel = it.items[it.at]
      #|  -> [{source_name: "T", component: "T", fields: [{name: "items", binding: "items", ty: TyList(TyAny), doc: None, attrs: []}, {name: "at", binding: "at", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [{name: "sel", source: ".items[.at]",span:_}], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    provide Cell = self
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [{name: "Cell", source: "self",span:_}], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    lookup theme
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [{name: "theme", default: None,span:_}], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    lookup theme = "plain"
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [{name: "theme", default: Some("'plain'"),span:_}], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    lookup n = 0
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [{name: "n", default: Some("0"),span:_}], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    lookup on = true
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [{name: "on", default: Some("true"),span:_}], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|field n :: Int
      #|    lookup v = null
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [{name: "v", default: Some("null"),span:_}], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|
    ),
  )
}

///|
/// The declarations beside a component, and what a component says about one.
test "types, protocols and the bindings to them, as they read" {
  let files = [
    "spec:\n  struct Line(what :: String, qty :: Int)\n\n  T:\n    field n :: Int\n",
    "spec:\n  enum Tone:\n    calm\n    loud\n\n  T:\n    field n :: Int\n", "spec:\n  enum Pick:\n    none_\n    one(String)\n\n  T:\n    field n :: Int\n",
    "spec:\n  protocol Holder = \"x/Holder@1\":\n    message hold(Any)\n    property filled :: Bool\n\n  T:\n    field n :: Int\n",
    "spec:\n  protocol Editable = \"x/Editable@1\":\n    view editor\n\n  T:\n    field n :: Int\n    implements Editable\n    view Editable::editor = chrome\n",
    "spec:\n  protocol Holder = \"x/Holder@1\":\n    property filled :: Bool\n\n  T:\n    field n :: Int\n    implements Holder\n    property filled :: Bool ~public\n    property Holder::filled = filled\n",
    "spec:\n  T:\n    field rows :: List.of(Any)\n    field at :: Int\n    where it.at is_index_of it.rows\n",
    "spec:\n  T:\n    field rows :: Map.of(String, Any)\n    field k :: String\n    where it.k is_key_of it.rows\n",
    "spec:\n  T:\n    field s :: String\n    where it.s len <= 100\n",
  ]
  let out = StringBuilder()
  for f in files {
    out.write_string(f.trim().to_owned() + "\n  -> " + read_defs(f) + "\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|spec:
      #|  struct Line(what :: String, qty :: Int)
      #|
      #|  T:
      #|    field n :: Int
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [{source_name: "Line", name: "TLine", kind: URecord([{name: "what", binding: "what", ty: TyText, doc: None, attrs: []}, {name: "qty", binding: "qty", ty: TyInt(width=32, signed=true), doc: None, attrs: []}]), doc: None}], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  enum Tone:
      #|    calm
      #|    loud
      #|
      #|  T:
      #|    field n :: Int
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [{source_name: "Tone", name: "TTone", kind: UEnum([("calm", "Calm"), ("loud", "Loud")]), doc: None}], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  enum Pick:
      #|    none_
      #|    one(String)
      #|
      #|  T:
      #|    field n :: Int
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [{source_name: "Pick", name: "TPick", kind: UVariant([{source_name: "none_", name: "none_", variant: "None", payload: [], variadic: false, doc: None}, {source_name: "one", name: "one", variant: "One", payload: [TyText], variadic: false, doc: None}]), doc: None}], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  protocol Holder = "x/Holder@1":
      #|    message hold(Any)
      #|    property filled :: Bool
      #|
      #|  T:
      #|    field n :: Int
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [{local_name: "Holder", id: "x/Holder@1", handle_message: [{source_name: "hold", name: "hold", variant: "Hold", payload: [TyAny], variadic: false, doc: None}], handle_intent: [], express_message: [], express_intent: [], properties: [{name: "filled", ty: TyBool, public_: true, writable: false, getter: None, setter: None, doc: None}], views: [], provides: [], lookups: [], doc: None,span:_}], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  protocol Editable = "x/Editable@1":
      #|    view editor
      #|
      #|  T:
      #|    field n :: Int
      #|    implements Editable
      #|    view Editable::editor = chrome
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: ["x/Editable@1"], protocols: [{local_name: "Editable", id: "x/Editable@1", handle_message: [], handle_intent: [], express_message: [], express_intent: [], properties: [], views: ["editor"], provides: [], lookups: [], doc: None,span:_}], protocol_imports: [], property_bindings: [], view_bindings: [{protocol_id: "x/Editable@1", member_name: "editor", source: "chrome",span:_}], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  protocol Holder = "x/Holder@1":
      #|    property filled :: Bool
      #|
      #|  T:
      #|    field n :: Int
      #|    implements Holder
      #|    property filled :: Bool ~public
      #|    property Holder::filled = filled
      #|  -> [{source_name: "T", component: "T", fields: [{name: "n", binding: "n", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [{name: "filled", ty: TyBool, public_: true, writable: false, getter: None, setter: None, doc: None}], receive: [], intent: [], express_message: [], express_intent: [], implements: ["x/Holder@1"], protocols: [{local_name: "Holder", id: "x/Holder@1", handle_message: [], handle_intent: [], express_message: [], express_intent: [], properties: [{name: "filled", ty: TyBool, public_: true, writable: false, getter: None, setter: None, doc: None}], views: [], provides: [], lookups: [], doc: None,span:_}], protocol_imports: [], property_bindings: [{protocol_id: "x/Holder@1", member_name: "filled", source: "filled",span:_}], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [], doc: None, category: "", keywords: []}]
      #|spec:
      #|  T:
      #|    field rows :: List.of(Any)
      #|    field at :: Int
      #|    where it.at is_index_of it.rows
      #|  -> [{source_name: "T", component: "T", fields: [{name: "rows", binding: "rows", ty: TyList(TyAny), doc: None, attrs: []}, {name: "at", binding: "at", ty: TyInt(width=32, signed=true), doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "at", subject_span:_, relation: DIndexOf(field="rows", allow_none=false), ref_span:_)], doc: None,span:_}], doc: None, category: "", keywords: []}]
      #|spec:
      #|  T:
      #|    field rows :: Map.of(String, Any)
      #|    field k :: String
      #|    where it.k is_key_of it.rows
      #|  -> [{source_name: "T", component: "T", fields: [{name: "rows", binding: "rows", ty: TyOMap(TyAny), doc: None, attrs: []}, {name: "k", binding: "k", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "k", subject_span:_, relation: DKeyOf(field="rows"), ref_span:_)], doc: None,span:_}], doc: None, category: "", keywords: []}]
      #|spec:
      #|  T:
      #|    field s :: String
      #|    where it.s len <= 100
      #|  -> [{source_name: "T", component: "T", fields: [{name: "s", binding: "s", ty: TyText, doc: None, attrs: []}], properties: [], receive: [], intent: [], express_message: [], express_intent: [], implements: [], protocols: [], protocol_imports: [], property_bindings: [], view_bindings: [], provide_bindings: [], lookup_bindings: [], types: [], provide: [], lookup: [], rules: [], wheres: [{subject: "s", subject_span:_, relation: DLen(DCompare(op=DLe, rhs=DLit(100))), ref_span:_}], doc: None, category: "", keywords: []}]
      #|
    ),
  )
}

///|
/// A default the printer could not carry.
///
/// `@component.lookup_or("entries", "[]")` is the documented MoonBit spelling
/// of an empty-collection fallback, and the lowering refused the `.tutu` line
/// that means it — "a list or map literal has no place in an expression",
/// which is true of an expression and not of this. So there is no other side
/// to agree with here, and the assertion is that the direct reader reads it.
test "an empty collection is a lookup default the lowering could not print" {
  let src = "spec:\n  T:\n    field n :: Int\n    lookup xs = []\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Spec) is Some(section) else { fail("no spec section") }
  let defs = @statedef.state_of_tutu(section.decls, name="T")
  @debug.assert_eq(defs[0].lookup.map(l => (l.name, l.default)), [
    ("xs", Some("[]")),
  ])
}
