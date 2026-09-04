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
  /// The declarations the SCRIPT BLOCK wrote, without the rules synthesized
  /// from the spec block.
  ///
  /// `decls` above is what gets compiled and is both; this is what gets
  /// CHECKED. `RULE_IN_BOTH` asks whether an author wrote one rule twice, and
  /// handing it a synthesized copy makes every spec-block rule its own
  /// duplicate.
  authored : Array[@tscript.Decl]
  /// The card's templates, carried through so the manifest can name them. A
  /// component with no view has nothing to mount.
  views : Array[@viewfile.RawView]
  common_style : String
  /// Every component the CARD declares, this one included.
  ///
  /// `new Swatch` names a sibling, and whether a name is one is a fact about
  /// the file rather than about the component reading it.
  siblings : Array[String]
  /// The card's named starting states.
  ///
  /// A fixture is not decoration: the DEFAULT one is what a host mounts when it
  /// is told no other name, so a card whose fixtures are dropped mounts at its
  /// declared zero and every string field renders empty. That is what dropping
  /// them looks like on a page, and it is why they are carried.
  inits : Array[@statedef.InitState]
  refusals : Array[@check.Refusal]
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
fn emit_shell(src : Src, comps : Array[Comp], manifest : @tutuca.Value) -> Unit {
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

  // A descriptor PER COMPONENT, and it is that component's slice of the ONE
  // manifest rather than a second description of it.
  //
  // `desc` is how an instance says what it is, and a host reads `component` off
  // it to decide which view to draw. A card declaring several components whose
  // children all carried the module's descriptor drew the root's view for every
  // child, which looked like the page repeating itself.
  let by_name = component_descriptors(manifest)
  for c in comps {
    src.open("fn \{c.id}_desc() -> &tg_val {")
    src.line(value_expr(by_name.get(c.name).unwrap_or(Null)))
    src.close("}")
    src.blank()
  }

  src.line("#[export = \"\{@abi.export_make}\"]")
  src.open("fn tgc_make(name: &tg_bytes, args: &?tg_val) -> &?tg_inst {")
  for c in comps {
    src.open("if str_eq(name, \{wax_str(c.name)}) != 0 {")
    src.line("return \{c.id}_inst(\{c.id}_desc(), \{c.id}_make_fields(args));")
    src.close("}")
  }
  src.line("null")
  src.close("}")
  src.blank()

  // The WHOLE manifest, in the module. A module that says what it is needs no
  // packer and no file beside it — which is what lets a toolchain that has
  // never heard of this repository produce one, and what stops a card arriving
  // with half of itself.
  //
  // It names the root component first, because every mount site takes the head
  // of `components`.
  src.line("#[export = \"\{@abi.export_describe}\"]")
  src.open("fn tgc_describe() -> &tg_val {")
  src.line(value_expr(manifest))
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
/// The manifest's components, by name — so an instance's descriptor is a slice
/// of the module's rather than a second copy of the same facts.
fn component_descriptors(
  manifest : @tutuca.Value,
) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  guard manifest is Map(m) && m.get("components") is Some(List(items)) else {
    return out
  }
  for item in items {
    if item is Map(c) && c.get("name") is Some(Str(name)) {
      out[name] = item
    }
  }
  out
}
