///| Blackbox tests: the declared shape out as JSON Schema, and JSON back in as
/// constructor arguments. The two halves are tested against each OTHER where
/// it matters — a value the schema advertises as legal must coerce, and one it
/// forbids must not — because a form and a tool that disagree is exactly the
/// failure this package exists to prevent.

///|
fn schema_of(fields : Array[@tutuca.FieldInfo]) -> @tutuca.SchemaInfo {
  @tutuca.SchemaInfo::new(name="Sample", fingerprint="test", fields~)
}

///|
fn compact(j : Json) -> String {
  j.stringify()
}

///|
/// One key of a JSON object. `Json::value` is deprecated in favour of the
/// pattern match, and the tests read keys constantly, so it lives here once.
fn at(j : Json, key : String) -> Json? {
  if j is Object(m) {
    m.get(key)
  } else {
    None
  }
}

///|
test "scalars project to their JSON Schema types" {
  let s = schema_of([
    @tutuca.FieldInfo::new("flag", TyBool),
    @tutuca.FieldInfo::new("n", TyInt),
    @tutuca.FieldInfo::new("x", TyFloat),
    @tutuca.FieldInfo::new("name", TyText),
  ])
  let js = of_schema(s)
  inspect(
    compact(at(js, "properties").unwrap()),
    content=(
      #|{"flag":{"type":"boolean"},"n":{"type":"integer"},"x":{"type":"number"},"name":{"type":"string"}}
    ),
  )
  // s32 and f64 are different declared types and must stay different here:
  // reading the kind off a seed value is what used to conflate them.
  inspect(compact(at(js, "title").unwrap()), content="\"Sample\"")
}

///|
test "collections carry their element type" {
  let s = schema_of([
    @tutuca.FieldInfo::new("tags", TyList(TyText)),
    @tutuca.FieldInfo::new("scores", TyOMap(TyFloat)),
    @tutuca.FieldInfo::new("pair", TyTuple([TyText, TyInt])),
    @tutuca.FieldInfo::new("open", TySet),
    @tutuca.FieldInfo::new("closed", TyFlags("size", ["s", "m", "l"])),
  ])
  let props = at(of_schema(s), "properties").unwrap()
  inspect(
    compact(at(props, "tags").unwrap()),
    content=(
      #|{"type":"array","items":{"type":"string"}}
    ),
  )
  inspect(
    compact(at(props, "scores").unwrap()),
    content=(
      #|{"type":"object","additionalProperties":{"type":"number"}}
    ),
  )
  // a tuple is fixed-length: prefixItems pins the members, `items: false`
  // forbids a third
  inspect(
    compact(at(props, "pair").unwrap()),
    content=(
      #|{"type":"array","prefixItems":[{"type":"string"},{"type":"integer"}],"items":false,"minItems":2}
    ),
  )
  // both sets are arrays of unique strings; only the closed one enumerates
  inspect(
    compact(at(props, "open").unwrap()),
    content=(
      #|{"type":"array","uniqueItems":true,"items":{"type":"string"}}
    ),
  )
  inspect(
    compact(at(props, "closed").unwrap()),
    content=(
      #|{"type":"array","uniqueItems":true,"items":{"enum":["s","m","l"]}}
    ),
  )
}

///|
/// The declared schema knows a record's NAME and not its fields. The honest
/// projection says so: a titled `$defs` entry that constrains nothing, rather
/// than a `type: object` that would be inventing a fact (a declared `enum` is
/// a string, not an object).
test "a named type becomes a titled but unconstrained $ref" {
  let s = schema_of([
    @tutuca.FieldInfo::new("item", TyRecord("todo-item")),
    @tutuca.FieldInfo::new("items", TyList(TyRecord("todo-item"))),
    @tutuca.FieldInfo::new("mode", TyEnum("mode")),
  ])
  let js = of_schema(s)
  let props = at(js, "properties").unwrap()
  inspect(
    compact(at(props, "item").unwrap()),
    content=(
      #|{"$ref":"#/$defs/todo-item"}
    ),
  )
  // met twice, defined once
  inspect(
    compact(at(props, "items").unwrap()),
    content=(
      #|{"type":"array","items":{"$ref":"#/$defs/todo-item"}}
    ),
  )
  inspect(
    compact(at(js, "$defs").unwrap()),
    content=(
      #|{"todo-item":{"title":"todo-item"},"mode":{"title":"mode"}}
    ),
  )
}

///|
/// A component slot is not an inline value: the host builds the child, so what
/// a caller can supply is a REFERENCE, which is what the surface patch
/// algebra's BindInstance takes.
test "a component slot becomes a component reference" {
  let s = schema_of([
    @tutuca.FieldInfo::new("left", TyComp(Some("Counter"))),
    @tutuca.FieldInfo::new("any", TyComp(None)),
  ])
  let js = of_schema(s)
  let props = at(js, "properties").unwrap()
  inspect(
    compact(at(props, "left").unwrap()),
    content=(
      #|{"$ref":"#/$defs/componentRef","description":"Must be a Counter."}
    ),
  )
  // the bare `component` marker names nothing, so it says nothing
  inspect(
    compact(at(props, "any").unwrap()),
    content=(
      #|{"$ref":"#/$defs/componentRef"}
    ),
  )
  let def = at(at(js, "$defs").unwrap(), "componentRef").unwrap()
  inspect(
    compact(at(def, "required").unwrap()),
    content="[\"module\",\"name\"]",
  )
}

///|
test "`any` projects to JSON Schema's `true`, which permits anything" {
  let s = schema_of([@tutuca.FieldInfo::new("blob", TyAny)])
  inspect(
    compact(at(of_schema(s), "properties").unwrap()),
    content="{\"blob\":true}",
  )
}

///|
test "a constraint supplies the half a type cannot state" {
  let s = schema_of([
    @tutuca.FieldInfo::new("email", TyText),
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("tags", TyList(TyText)),
  ])
  let docs : Map[String, FieldDoc] = {
    "email": {
      doc: "Where to write.",
      required: true,
      constraint: Some({
        ..Constraint::none(),
        max_len: Some(254),
        format: "email",
        default: Some(Str("a@b.c")),
      }),
    },
    "count": {
      doc: "",
      required: false,
      constraint: Some({ ..Constraint::none(), min: Some(0), max: Some(10) }),
    },
    "tags": {
      doc: "",
      required: false,
      constraint: Some({ ..Constraint::none(), max_len: Some(3) }),
    },
  }
  let js = of_schema(s, docs~)
  let props = at(js, "properties").unwrap()
  // a length is characters on text...
  inspect(
    compact(at(props, "email").unwrap()),
    content=(
      #|{"type":"string","maxLength":254,"format":"email","default":"a@b.c","description":"Where to write."}
    ),
  )
  // ...and elements on a collection: the same declared `max_len` picks the
  // keyword the type calls for
  inspect(
    compact(at(props, "tags").unwrap()),
    content=(
      #|{"type":"array","items":{"type":"string"},"maxItems":3}
    ),
  )
  inspect(
    compact(at(props, "count").unwrap()),
    content=(
      #|{"type":"integer","minimum":0,"maximum":10}
    ),
  )
  inspect(compact(at(js, "required").unwrap()), content="[\"email\"]")
}

///|
/// `option<T>` says the absence is a legal value. A manifest that also marked
/// the field required would be contradicting its own type, and the type wins —
/// it is the half the guest's decoder actually enforces.
test "an optional type is never required, whatever the manifest claimed" {
  let s = schema_of([@tutuca.FieldInfo::new("note", TyOption(TyText))])
  let docs : Map[String, FieldDoc] = {
    "note": { doc: "", required: true, constraint: None },
  }
  let js = of_schema(s, docs~)
  // the option unwraps: the field's schema is its element's
  inspect(
    compact(at(js, "properties").unwrap()),
    content=(
      #|{"note":{"type":"string"}}
    ),
  )
  assert_true(at(js, "required") is None)
}

// --- the reverse direction -------------------------------------------------

///|
test "well-typed JSON becomes constructor arguments" {
  let s = schema_of([
    @tutuca.FieldInfo::new("name", TyText),
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("tags", TyList(TyText)),
    @tutuca.FieldInfo::new("flag", TyBool),
  ])
  let j = @json.parse(
    (
      #|{"name": "a", "count": 3, "tags": ["x", "y"], "flag": true}
    ),
  )
  guard! coerce(s, j) is Ok(args)
  debug_inspect(
    args,
    content=(
      #|{
      #|  "name": RStr("a"),
      #|  "count": RNum(3),
      #|  "tags": RList([RStr("x"), RStr("y")]),
      #|  "flag": RBool(true),
      #|}
    ),
  )
}

///|
/// Every error, not the first one. A caller that fixed one field per round
/// trip would take as many round trips as it has mistakes, which is the thing
/// that makes a tool call unusable to a model and a form unpleasant to a
/// person.
test "errors are collected, and each points at where it happened" {
  let s = schema_of([
    @tutuca.FieldInfo::new("name", TyText),
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("tags", TyList(TyText)),
  ])
  let j = @json.parse(
    (
      #|{"name": 1, "count": 1.5, "tags": ["ok", 2], "extra": true}
    ),
  )
  guard! coerce(s, j) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|[
      #|  "/name: expected String, got number",
      #|  "/count: expected an integer, got 1.5",
      #|  "/tags/1: expected String, got number",
      #|  "/extra: no such field",
      #|]
    ),
  )
}

///|
/// A key outside the schema is a typo or a misunderstanding, and both are
/// worth saying. The EMITTED schema stays open — a constructor may take more
/// than the declared fields — but this side has a name to complain about.
test "a required field that is missing is named" {
  let s = schema_of([
    @tutuca.FieldInfo::new("email", TyText),
    @tutuca.FieldInfo::new("note", TyText),
  ])
  let docs : Map[String, FieldDoc] = {
    "email": { doc: "", required: true, constraint: None },
  }
  guard! coerce(s, @json.parse("{}"), docs~) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|["/email: required"]
    ),
  )
  // and the un-required one is simply ABSENT rather than filled with its zero:
  // what an unsupplied field means is the constructor's decision
  guard! coerce(s, @json.parse("{\"email\": \"a\"}"), docs~) is Ok(args)
  debug_inspect(args.keys().collect(), content="[\"email\"]")
}

///|
test "a constraint is checked on the way in, not only advertised" {
  let s = schema_of([
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("name", TyText),
    @tutuca.FieldInfo::new("mode", TyText),
  ])
  let docs : Map[String, FieldDoc] = {
    "count": {
      doc: "",
      required: false,
      constraint: Some({ ..Constraint::none(), min: Some(0), max: Some(10) }),
    },
    "name": {
      doc: "",
      required: false,
      constraint: Some({ ..Constraint::none(), min_len: Some(2) }),
    },
    "mode": {
      doc: "",
      required: false,
      constraint: Some({
        ..Constraint::none(),
        enum_values: Some([Str("on"), Str("off")]),
      }),
    },
  }
  let j = @json.parse(
    (
      #|{"count": 42, "name": "x", "mode": "maybe"}
    ),
  )
  guard! coerce(s, j, docs~) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|[
      #|  "/count: must be at most 10, got 42",
      #|  "/name: must have at least 2 characters, got 1",
      #|  "/mode: must be one of on, off",
      #|]
    ),
  )
  // the same document inside the bounds passes
  let ok = @json.parse(
    (
      #|{"count": 3, "name": "xy", "mode": "on"}
    ),
  )
  assert_true(coerce(s, ok, docs~) is Ok(_))
}

///|
/// A closed set enumerates its members, and that enumeration is the one thing
/// about it only the schema knows — the encoded value is just a Map.
test "a closed set rejects a non-member; an open one takes anything" {
  let s = schema_of([
    @tutuca.FieldInfo::new("size", TyFlags("size", ["s", "m"])),
    @tutuca.FieldInfo::new("free", TySet),
  ])
  guard! coerce(
      s,
      @json.parse("{\"size\": [\"s\", \"xl\"], \"free\": [\"q\"]}"),
    )
    is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|["/size/1: not a member: xl (expected one of s, m)"]
    ),
  )
  // and a set is HELD as a map, which is the refinement TySet names
  guard! coerce(s, @json.parse("{\"size\": [\"s\"], \"free\": [\"q\"]}"))
    is Ok(args)
  debug_inspect(
    args,
    content=(
      #|{
      #|  "size": RMap({ "s": RBool(true) }),
      #|  "free": RMap({ "q": RBool(true) }),
      #|}
    ),
  )
}

///|
/// The two halves have to agree, and this is the cheapest way to keep them
/// honest: what the schema says is required is what coerce demands, and what
/// it says the type is, is what coerce accepts.
test "what the emitted schema advertises is what coerce accepts" {
  let s = schema_of([
    @tutuca.FieldInfo::new("email", TyText),
    @tutuca.FieldInfo::new("note", TyOption(TyText)),
  ])
  let docs : Map[String, FieldDoc] = {
    "email": { doc: "", required: true, constraint: None },
    "note": { doc: "", required: true, constraint: None },
  }
  let js = of_schema(s, docs~)
  // the schema requires exactly `email` — `note` is optional by type
  inspect(compact(at(js, "required").unwrap()), content="[\"email\"]")
  // ...and so does coerce
  assert_true(coerce(s, @json.parse("{\"email\": \"a\"}"), docs~) is Ok(_))
  guard! coerce(s, @json.parse("{\"note\": \"n\"}"), docs~) is Err(errors)
  debug_inspect(errors.map(e => e.pointer), content="[\"/email\"]")
  // and an explicit null satisfies the optional
  assert_true(
    coerce(s, @json.parse("{\"email\": \"a\", \"note\": null}"), docs~) is Ok(_),
  )
}

///|
/// A guest names its own fields, so a field called `a/b` is a thing an
/// untrusted manifest can produce, and a pointer that did not escape it would
/// point somewhere else.
test "pointers escape per RFC 6901" {
  let s = schema_of([@tutuca.FieldInfo::new("a/b~c", TyText)])
  guard! coerce(s, @json.parse("{\"a/b~c\": 1}")) is Err(errors)
  debug_inspect(errors.map(e => e.pointer), content="[\"/a~1b~0c\"]")
}

///|
test "a non-object document fails at the root" {
  let s = schema_of([@tutuca.FieldInfo::new("a", TyText)])
  guard! coerce(s, @json.parse("[1, 2]")) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|[": expected an object, got array"]
    ),
  )
}

///|
test "a table field projects to a described $defs, not a titled stub" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let js = of_schema(s)
  inspect(
    compact(at(js, "properties").unwrap()),
    content=(
      #|{"data":{"$ref":"#/$defs/table"}}
    ),
  )
  // The point of the whole exercise: a record gets `{"title": "card"}` and
  // nothing else, while a table gets its actual shape.
  let defs = at(js, "$defs").unwrap()
  inspect(
    compact(at(at(defs, "colType").unwrap(), "enum").unwrap()),
    content=(
      #|["i32","f64","str","bool"]
    ),
  )
  inspect(
    compact(at(at(defs, "table").unwrap(), "required").unwrap()),
    content=(
      #|["columns"]
    ),
  )
  inspect(
    compact(at(at(defs, "column").unwrap(), "required").unwrap()),
    content=(
      #|["id","label","type","values"]
    ),
  )
  // The discriminated branches are what let a generator get typed values right.
  inspect(
    compact(at(at(defs, "column").unwrap(), "oneOf").unwrap()),
    content=(
      #|[{"properties":{"type":{"const":"i32"},"values":{"type":"array","items":{"type":["integer","null"],"minimum":-2147483648,"maximum":2147483647}}}},{"properties":{"type":{"const":"f64"},"values":{"type":"array","items":{"type":["number","null"]}}}},{"properties":{"type":{"const":"str"},"values":{"type":"array","items":{"type":["string","null"]}}}},{"properties":{"type":{"const":"bool"},"values":{"type":"array","items":{"type":["boolean","null"]}}}}]
    ),
  )
}

///|
test "two table fields share one set of $defs" {
  let s = schema_of([
    @tutuca.FieldInfo::new("left", TyTable),
    @tutuca.FieldInfo::new("right", TyTable),
  ])
  let defs = at(of_schema(s), "$defs").unwrap()
  guard! defs is Object(m)
  inspect(m.keys().to_array().length(), content="3")
}

///|
test "a well-formed table coerces, and rowCount is derived" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let j = @json.parse(
    (
      #|{"data": {"columns": [
      #|  {"id": "city", "label": "City", "type": "str", "values": ["Berlin", "Athens", "Lima"]},
      #|  {"id": "pop", "label": "Population", "type": "i32", "values": [3664000, 664000, null]},
      #|  {"id": "lat", "label": "Latitude", "type": "f64", "values": [52.52, 37.98, -12.05]},
      #|  {"id": "capital", "label": "Capital", "type": "bool", "values": [true, true, true]}]}}
    ),
  )
  guard! coerce(s, j) is Ok(args)
  inspect(
    args.get("data").unwrap().to_json().stringify(),
    content=(
      #|{"columns":[{"id":"city","label":"City","type":"str","values":["Berlin","Athens","Lima"]},{"id":"pop","label":"Population","type":"i32","values":[3664000,664000,null]},{"id":"lat","label":"Latitude","type":"f64","values":[52.52,37.98,-12.05]},{"id":"capital","label":"Capital","type":"bool","values":[true,true,true]}],"rowCount":3}
    ),
  )
}

///|
test "columns of unequal width are rejected — the check no JSON Schema can make" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let j = @json.parse(
    (
      #|{"data": {"columns": [
      #|  {"id": "city", "label": "City", "type": "str", "values": ["Berlin", "Athens", "Lima"]},
      #|  {"id": "pop", "label": "Population", "type": "i32", "values": [3664000, 664000]}]}}
    ),
  )
  guard! coerce(s, j) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|["/data/columns/1/values: 2 values, but column city has 3 — every column in a table must have the same number"]
    ),
  )
}

///|
test "a table with columns and no rows is valid" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let j = @json.parse(
    (
      #|{"data": {"columns": [{"id": "a", "label": "A", "type": "str", "values": []}]}}
    ),
  )
  guard! coerce(s, j) is Ok(args)
  inspect(
    args.get("data").unwrap().to_json().stringify(),
    content=(
      #|{"columns":[{"id":"a","label":"A","type":"str","values":[]}],"rowCount":0}
    ),
  )
}

///|
test "cell types, i32 range, duplicate ids and unknown keys are all reported" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let j = @json.parse(
    (
      #|{"data": {"columns": [
      #|  {"id": "n", "label": "N", "type": "i32", "values": [1, 2.5, 9007199254740993, "x"]},
      #|  {"id": "n", "label": "Again", "type": "nope", "values": [1, 2, 3, 4]},
      #|  {"id": "ok", "label": "Ok", "type": "bool", "values": [true, false, null, true], "width": 4}]}}
    ),
  )
  guard! coerce(s, j) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|[
      #|  "/data/columns/0/values/1: an i32 column holds whole numbers, got 2.5",
      #|  "/data/columns/0/values/2: not a safely represented integer — a value outside JSON's exact integer range belongs in a str column",
      #|  "/data/columns/0/values/3: expected i32 or null, got string",
      #|  "/data/columns/1/id: duplicate column id n, already used by column 0",
      #|  "/data/columns/1/type: expected one of i32, f64, str, bool, got nope",
      #|  "/data/columns/2/width: no such column field (expected one of id, label, type, values)",
      #|]
    ),
  )
}

///|
test "a stated rowCount that disagrees with the data is caught" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  let j = @json.parse(
    (
      #|{"data": {"rowCount": 9, "columns": [
      #|  {"id": "a", "label": "A", "type": "str", "values": ["x", "y"]}]}}
    ),
  )
  guard! coerce(s, j) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|["/data/rowCount: says 9, but the columns hold 2; leave it out and it is counted for you"]
    ),
  )
}

///|
test "a table that is not an object fails at the table, not inside it" {
  let s = schema_of([@tutuca.FieldInfo::new("data", TyTable)])
  guard! coerce(s, @json.parse("{\"data\": [1, 2]}")) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content=(
      #|["/data: expected a table object with a \"columns\" array, got array"]
    ),
  )
}

///|
/// A bound the type cannot carry does not reach the schema.
///
/// The manifest's constraint record spells "unstated" as `None` for the four
/// bounds and `""` for the strings beside it, so writing the record out in full
/// — which is what copying a sample guest's manifest teaches — states four
/// zeros nobody meant. Validation shrugs most of them off (`min`/`max` are
/// guarded by `v is Num`), but the SCHEMA is what an agent reads with nobody
/// there to ask, and `{"type":"string","minimum":0,"maximum":0}` tells it
/// something false about a timestamp.
test "a bound the type cannot carry never reaches the schema" {
  let s = schema_of([
    @tutuca.FieldInfo::new("createdAt", TyText),
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("on", TyBool),
    @tutuca.FieldInfo::new("tags", TyList(TyText)),
  ])
  let zeros = {
    ..Constraint::none(),
    min: Some(0),
    max: Some(0),
    max_len: Some(0),
  }
  let docs : Map[String, FieldDoc] = {
    "createdAt": {
      doc: "",
      required: false,
      constraint: Some({ ..zeros, format: "date-time", max_len: None }),
    },
    "count": {
      doc: "",
      required: false,
      constraint: Some({ ..zeros, max_len: None }),
    },
    "on": { doc: "", required: false, constraint: Some(zeros) },
    "tags": { doc: "", required: false, constraint: Some(zeros) },
  }
  let props = at(of_schema(s, docs~), "properties").unwrap()
  // a numeric bound says nothing about text, so it is dropped rather than
  // advertised
  inspect(
    compact(at(props, "createdAt").unwrap()),
    content=(
      #|{"type":"string","format":"date-time"}
    ),
  )
  // …while on a number it is a real bound, emitted as given — a stated zero
  // constrains, and this is not the place to second-guess one
  inspect(
    compact(at(props, "count").unwrap()),
    content=(
      #|{"type":"integer","minimum":0,"maximum":0}
    ),
  )
  // a bool has neither a length nor a magnitude
  inspect(
    compact(at(props, "on").unwrap()),
    content=(
      #|{"type":"boolean"}
    ),
  )
  // and a collection keeps the length under the keyword it uses, without the
  // numeric bounds beside it
  inspect(
    compact(at(props, "tags").unwrap()),
    content=(
      #|{"type":"array","items":{"type":"string"},"maxItems":0}
    ),
  )
}
