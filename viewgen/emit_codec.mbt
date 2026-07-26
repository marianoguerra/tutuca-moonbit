// Emitting direct state <-> Value codecs.
//
// The runtime bridges typed state to the Value world through JSON: `S ->
// Json -> Value` on the way in and back on the way out
// (component/instance.mbt encode_state / decode_state), once per state
// write. benchmarks/OPTIMIZATIONS.md flags the cost.
//
// With the schema in hand the conversion can be written out field by field,
// with no intermediate `Json` object. The interesting part is not the
// allocation saved but the fields that need NO conversion at all: an `any`
// or a child-slot field already holds a `@tutuca.Value`, and the whole
// reason `with_value_stash` exists is that those cannot survive a JSON round
// trip. A direct codec never sends them through one.
//
// Emitted for every schema-backed component whose fields all have a direct
// form, and passed to `component()` as `encode~`/`decode~`. Adopting it was
// gated on a measurement, because a second encoder has to be kept in step
// with the derived one: benchmarks/codec_bench_test.mbt puts encode at ~2x
// and decode at ~5x, decode gaining most because the JSON path rebuilds a
// whole `Json` object just to hand it to `from_json`.

///|
/// `<v>_encode` / `<v>_decode`, when every field has a direct form.
///
/// A component with a nested record, variant or enum field is skipped: those
/// have their own derived `ToJson`, and reimplementing it here would be a
/// second encoder to keep in step with the first for no measurable gain.
fn emit_codec(
  t : String,
  v : String,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  let carried = def.fields.filter(f => f.ty.in_struct())
  if carried.is_empty() || !carried.iter().all(f => direct(f.ty)) {
    return
  }
  out.write_string(
    "///|\n" +
    "/// The state as the fields map the render and path layers read, built\n" +
    "/// field by field rather than through a `Json` round trip.\n" +
    "///\n" +
    "/// A field that already holds a `@tutuca.Value` is passed straight\n" +
    "/// through: it is exactly what `with_value_stash` exists to rescue from\n" +
    "/// the JSON path, and this way it never enters one.\n" +
    "fn \{v}_encode(s : \{t}State) -> Map[String, @tutuca.Value] {\n" +
    "  {\n",
  )
  for f in carried {
    out.write_string(
      "    \{quote(f.name)}: \{enc_expr(f.ty, "s." + f.binding)},\n",
    )
  }
  out.write_string("  }\n}\n\n")
  out.write_string(
    "///|\n" +
    "/// The fields map back into the state. None on a shape mismatch, which\n" +
    "/// callers treat as a no-op write — the same contract as the JSON path.\n" +
    "fn \{v}_decode(f : Map[String, @tutuca.Value]) -> \{t}State? {\n",
  )
  for f in carried {
    out.write_string(dec_binding(f, def))
  }
  out.write_string("  Some(\{t}State::{\n")
  for f in carried {
    out.write_string("    \{f.binding}: v_\{f.binding},\n")
  }
  out.write_string("  })\n}\n\n")
}

///|
/// True when a type has a direct Value form that needs no derived codec.
fn direct(ty : @statedef.StateTy) -> Bool {
  match ty {
    TBool | TInt(..) | TFloat | TText | TAny | TSet | TFlags(_) => true
    TList(e) => direct(e)
    TOMap(e) => direct(e)
    _ => false
  }
}

///|
/// A field as a `@tutuca.Value`.
fn enc_expr(ty : @statedef.StateTy, e : String) -> String {
  match ty {
    TBool => "Bool(\{e})"
    TInt(..) => "Num(\{e}.to_double())"
    TFloat => "Num(\{e})"
    TText => "Str(\{e})"
    // Already a Value. This is the case the JSON path cannot do at all
    // without the stash.
    TAny => e
    TList(inner) =>
      "(List(\{e}.map(x => \{enc_expr(inner, "x")})) : @tutuca.Value)"
    TSet | TFlags(_) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, b in \{e} { m[k] = Bool(b) }; (Map(m) : @tutuca.Value) }"
    TOMap(inner) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, x in \{e} { m[k] = \{enc_expr(inner, "x")} }; (Map(m) : @tutuca.Value) }"
    _ => "Null"
  }
}

///|
/// The `let v_<field> = ...` line that pulls one field back out.
fn dec_binding(f : @statedef.FieldDef, def : @statedef.StateDef) -> String {
  let key = quote(f.name)
  let got = "f.get(\{key})"
  match f.ty {
    TAny => "  let v_\{f.binding} = \{got}.unwrap_or(Null)\n"
    TBool =>
      "  guard \{got} is Some(Bool(v_\{f.binding})) else { return None }\n"
    TFloat =>
      "  guard \{got} is Some(Num(v_\{f.binding})) else { return None }\n"
    TText =>
      "  guard \{got} is Some(Str(v_\{f.binding})) else { return None }\n"
    TInt(..) =>
      "  guard \{got} is Some(Num(n_\{f.binding})) else { return None }\n" +
      "  let v_\{f.binding} = n_\{f.binding}.to_int()\n"
    TList(inner) =>
      "  guard \{got} is Some(List(l_\{f.binding})) else { return None }\n" +
      "  let v_\{f.binding} : \{def.moonbit_ty(f.ty)} = []\n" +
      "  for x in l_\{f.binding} {\n" +
      "    \{dec_push(inner, "v_" + f.binding)}\n" +
      "  }\n"
    TSet | TFlags(_) =>
      "  guard \{got} is Some(Map(m_\{f.binding})) else { return None }\n" +
      "  let v_\{f.binding} : Map[String, Bool] = Map([])\n" +
      "  for k, x in m_\{f.binding} {\n" +
      "    v_\{f.binding}[k] = x is Bool(true)\n" +
      "  }\n"
    TOMap(inner) =>
      "  guard \{got} is Some(Map(m_\{f.binding})) else { return None }\n" +
      "  let v_\{f.binding} : \{def.moonbit_ty(f.ty)} = Map([])\n" +
      "  for k, x in m_\{f.binding} {\n" +
      "    \{dec_set(inner, "v_" + f.binding)}\n" +
      "  }\n"
    _ => "  let v_\{f.binding} : @tutuca.Value = Null\n"
  }
}

///|
fn dec_push(inner : @statedef.StateTy, target : String) -> String {
  match inner {
    TAny => "\{target}.push(x)"
    TBool => "if x is Bool(b) { \{target}.push(b) } else { return None }"
    TFloat => "if x is Num(n) { \{target}.push(n) } else { return None }"
    TInt(..) =>
      "if x is Num(n) { \{target}.push(n.to_int()) } else { return None }"
    TText => "if x is Str(s) { \{target}.push(s) } else { return None }"
    _ => "return None"
  }
}

///|
fn dec_set(inner : @statedef.StateTy, target : String) -> String {
  match inner {
    TAny => "\{target}[k] = x"
    TBool => "if x is Bool(b) { \{target}[k] = b } else { return None }"
    TFloat => "if x is Num(n) { \{target}[k] = n } else { return None }"
    TInt(..) =>
      "if x is Num(n) { \{target}[k] = n.to_int() } else { return None }"
    TText => "if x is Str(s) { \{target}[k] = s } else { return None }"
    _ => "return None"
  }
}
