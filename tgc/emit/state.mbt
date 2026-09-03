// The state, and the four things every component owes a host.
//
// Every field is one slot in a `&tg_vals`, whatever its declared type. That is
// a deliberate simplification and worth stating: a specialising backend would
// unbox an `Int` field into an `f64` field of a generated struct and save a
// `struct.new` per assignment. This one does not, and gets `get_field` and
// `with_field` for two lines each, a successor that shares every slot it did
// not change, and no per-type code path to get subtly wrong. The declared type
// still decides the ZERO and still truncates an `Int` at its assignment sites,
// which is where the semantics actually live.

///|
/// One component's compiled shape: everything the emitters need to name it.
priv struct Comp {
  def : @statedef.StateDef
  /// The card's own name, as a host asks for it.
  name : String
  /// That name as a Wax identifier prefix.
  id : String
  /// Declared fields, in declaration order. The index IS the slot.
  fields : Array[@statedef.FieldDef]
  decls : Array[@tscript.Decl]
  /// The card's templates, carried through so the manifest can name them. A
  /// component with no view has nothing to mount.
  views : Array[@viewfile.RawView]
  common_style : String
  /// The card's named starting states.
  ///
  /// A fixture is not decoration: the DEFAULT one is what a host mounts when it
  /// is told no other name, so a card whose fixtures are dropped mounts at its
  /// declared zero and every string field renders empty. That is what dropping
  /// them looks like on a page, and it is why they are carried.
  inits : Array[@statedef.InitState]
  refusals : Array[Refusal]
}

///|
fn Comp::field_index(self : Comp, name : String) -> Int? {
  for i, f in self.fields {
    if f.name == name {
      return Some(i)
    }
  }
  None
}

///|
/// The zero of a declared type, as a Wax expression.
///
/// `Ty::zero` already answers it as a `Value`, so this is only the spelling —
/// which matters because a card and a compiled component must start from the
/// same state, and two zero tables would eventually disagree.
fn zero_expr(ty : @tutuca.Ty) -> String {
  value_expr(ty.zero())
}

///|
/// A constant `Value` as a Wax expression.
fn value_expr(v : @tutuca.Value) -> String {
  match v {
    Null => "tg_null()"
    Bool(b) => "tg_bool(\{if b { 1 } else { 0 }})"
    Num(n) => "tg_num(\{wax_num(n)})"
    Str(s) => "tg_str(\{wax_str(s)})"
    List(items) => {
      if items.length() == 0 {
        return "tg_list([tg_vals| null; 0])"
      }
      let parts = items.map(value_expr)
      "tg_list([tg_vals| " + parts.join(", ") + "])"
    }
    Map(m) => {
      if m.length() == 0 {
        return "tg_map([tg_entries| null; 0])"
      }
      let parts = []
      for k, item in m {
        parts.push("tg_entry_of(\{wax_str(k)}, \{value_expr(item)})")
      }
      "tg_map([tg_entries| " + parts.join(", ") + "])"
    }
    // A function and a component instance are not constants a schema can hold.
    // `Ty::zero` never answers one; a fixture might, and this is where that
    // would be caught rather than emitted as something plausible.
    _ => "tg_null()"
  }
}

///|
/// The state type, the field table, and the two vtable slots' data half.
fn emit_state(src : Src, c : Comp) -> Unit {
  let n = c.fields.length()
  src.line("// ── \{c.name} ──")
  src.blank()
  src.line("// Every declared field is one slot. The index is the field.")
  src.line("type \{c.id}_state = { fields: &tg_vals };")
  src.blank()

  // The name -> slot table. An if-chain rather than a hash: a card has a
  // handful of fields, and a chain the reader can follow beats a table nobody
  // can check by eye.
  src.open("fn \{c.id}_slot(name: &tg_bytes) -> i32 {")
  for i, f in c.fields {
    src.line("if str_eq(name, \{wax_str(f.name)}) != 0 { return \{i}; }")
  }
  src.line("-1")
  src.close("}")
  src.blank()

  src.line("// Absence, not null-the-value: there is no such field.")
  src.open(
    "fn \{c.id}_get: tg_get(self: &tg_inst, name: &tg_bytes) -> &?tg_val {",
  )
  src.line("let st = self.state! as &\{c.id}_state;")
  src.line("let i = \{c.id}_slot(name);")
  src.line("if i <s 0 { return null; }")
  src.line("st.fields[i]")
  src.close("}")
  src.blank()

  src.line(
    "// Copy on write. The successor shares every slot it did not change.",
  )
  src.open("fn \{c.id}_copy(st: &\{c.id}_state) -> &tg_vals {")
  src.line("let out = [tg_vals| null; \{n}];")
  src.line("let i: i32 = 0;")
  src.open("while i <s \{n} {")
  src.line("out[i] = st.fields[i];")
  src.line("i += 1;")
  src.close("}")
  src.line("out")
  src.close("}")
  src.blank()
}

///|
/// `tgc.make`, `tgc.describe` and the instance constructor.
fn emit_shell(src : Src, comps : Array[Comp], module_name : String) -> Unit {
  src.line("// ── the four exports ──")
  src.blank()
  src.line("let \{ID_COUNTER}: i64 = 0;")
  src.blank()
  for c in comps {
    src.open("fn \{c.id}_inst(desc: &tg_val, fields: &tg_vals) -> &tg_inst {")
    src.line("\{ID_COUNTER} = \{ID_COUNTER} + (1 as i64);")
    src.line("let vt: &tg_vt = { get: \{c.id}_get, call: \{c.id}_call };")
    src.line("let st: &\{c.id}_state = { fields };")
    src.line("let out: &tg_inst = { vt, desc, state: st, id: \{ID_COUNTER} };")
    src.line("out")
    src.close("}")
    src.blank()
  }

  // Construction from a host's argument map. A missing or oddly-shaped `args`
  // is the declared zero rather than a refusal: a host that hands a component
  // nothing has asked for its initial state, and that is a thing a component
  // knows.
  for c in comps {
    src.open("fn \{c.id}_make_fields(args: &?tg_val) -> &tg_vals {")
    src.line("let out = [tg_vals| null; \{c.fields.length()}];")
    for i, f in c.fields {
      src.line(
        "out[\{i}] = tg_arg(args, \{wax_str(f.name)}, \{zero_expr(f.ty)});",
      )
    }
    src.line("out")
    src.close("}")
    src.blank()
  }

  src.line("#[export = \"\{@abi.export_make}\"]")
  src.open("fn tgc_make(name: &tg_bytes, args: &?tg_val) -> &?tg_inst {")
  for c in comps {
    src.open("if str_eq(name, \{wax_str(c.name)}) != 0 {")
    src.line("return \{c.id}_inst(tgc_describe(), \{c.id}_make_fields(args));")
    src.close("}")
  }
  src.line("null")
  src.close("}")
  src.blank()

  src.line(
    "// The manifest, as an ordinary value. A module that says what it is",
  )
  src.line("// needs no packer and no file beside it.")
  src.line("#[export = \"\{@abi.export_describe}\"]")
  src.open("fn tgc_describe() -> &tg_val {")
  src.line("tg_map([tg_entries|")
  src.depth = src.depth + 1
  src.line("tg_entry_of(\"module\", tg_str(\{wax_str(module_name)})),")
  src.line("tg_entry_of(\"component\", tg_str(\{wax_str(comps[0].name)})),")
  src.line("tg_entry_of(\"protocols\", \{str_list(comps[0].def.implements)}),")
  src.line("tg_entry_of(\"components\", \{str_list(comps.map(c => c.name))}),")
  src.line(
    "tg_entry_of(\"fields\", \{str_list(comps[0].fields.map(f => f.name))}),",
  )
  src.line(
    "tg_entry_of(\"receives\", \{str_list(answered(comps[0], DReceive))}),",
  )
  src.line(
    "tg_entry_of(\"intents\", \{str_list(answered(comps[0], DAnswer))}),",
  )
  src.line(
    "tg_entry_of(\"methods\", \{str_list(answered(comps[0], DCompute))}),",
  )
  src.depth = src.depth - 1
  src.line("])")
  src.close("}")
  src.blank()

  src.line("// This card serves no module-scoped intent. A `serve` block would")
  src.line("// answer here, on the `lex` leg.")
  src.line("#[export = \"\{@abi.export_serve}\"]")
  src.line("fn tgc_serve(name: &tg_bytes, args: &tg_vals) -> &?tg_val { null }")
  src.blank()
  src.line("#[export = \"\{@abi.export_abi}\"]")
  src.line("fn tgc_abi() -> i32 { \{@abi.ABI_VERSION} }")
}

///|
/// The one mutable global a generated module has: instance identity.
///
/// It is per MODULE rather than per component, so two instances of two
/// components never share an id — identity is what drives change detection, and
/// a collision there is a re-render that does not happen.
const ID_COUNTER : String = "tgc_next_id"

///|
/// The names a component actually answers for a kind — refusals excluded,
/// because a manifest that named a refused handler would tell a host the
/// component answers something it does not.
fn answered(c : Comp, kind : @tscript.DeclKind) -> Array[String] {
  let out = []
  for d in c.decls {
    if d.kind == kind && !c.refusals.iter().any(r => r.name == d.name) {
      out.push(d.name)
    }
  }
  out
}

///|
fn str_list(items : Array[String]) -> String {
  if items.length() == 0 {
    return "tg_list([tg_vals| null; 0])"
  }
  let parts = items.map(s => "tg_str(\{wax_str(s)})")
  "tg_list([tg_vals| " + parts.join(", ") + "])"
}
