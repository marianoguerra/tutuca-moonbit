// Emitting a dyncomp guest's state accessors.
//
// A guest module implements `tutuca:component`'s `instance` resource, and
// four of its methods are pure functions of the state's shape: `get-field`,
// `with-field`, `to-json` and `seq-entries`. Before the schema every guest
// wrote all four by hand as string matches — 246 lines in guests/counter,
// and again in Rust for guests/rust-counter — and a field added to one and
// not the others failed silently at the boundary.
//
// What is NOT emitted is `handle`, `call-method` or the component-def's
// handler lists. Those are behaviour, and behaviour is what a guest is FOR.
// The split is the point: the schema owns the shape, the author owns the
// conduct.
//
// The value type here is the WIT-generated `@values.Value`, not
// `@tutuca.Value` — a guest is on the other side of the boundary, where
// compounds travel as arena handles rather than as MoonBit collections.

///|
/// The state struct and its four shape-derived accessors, for one component.
///
/// `trait_name` and `values` name the guest's own SDK so this does not hard-
/// code one bindgen layout; the defaults match guests/counter.
pub fn to_guest(
  def : StateDef,
  trait_name? : String = "DynComponent",
  values? : String = "@values",
) -> String {
  let out = StringBuilder::new()
  let t = def.component
  out.write_string(
    "// GENERATED from the tutuca/state block — DO NOT EDIT.\n" +
    "//\n" +
    "// The SHAPE half of the `instance` resource: get-field, with-field,\n" +
    "// to-json and seq-entries are functions of the state's fields, so they\n" +
    "// are derived. `handle` and `call_method` are behaviour and stay hand-\n" +
    "// written alongside this file.\n" +
    "//\n" +
    "// schema fingerprint: \{fingerprint([def])}\n\n",
  )
  // -- the struct -----------------------------------------------------------
  out.write_string("///|\npriv struct \{t} {\n")
  for f in def.fields {
    out.write_string("  \{f.binding} : \{guest_ty(def, f.ty)}\n")
  }
  out.write_string("}\n\n")
  // -- get_field ------------------------------------------------------------
  out.write_string(
    "///|\n" +
    "/// Lazy field read: the host calls this while rendering, one field at a\n" +
    "/// time, rather than marshalling the whole state across.\n" +
    "impl \{trait_name} for \{t} with fn get_field(self, name) {\n" +
    "  match name {\n",
  )
  for f in def.fields {
    out.write_string(
      "    \{quote(f.name)} => Some(\{to_guest_value(def, f.ty, "self." + f.binding, values)})\n",
    )
  }
  out.write_string("    _ => None\n  }\n}\n\n")
  // -- with_field -----------------------------------------------------------
  out.write_string(
    "///|\n" +
    "/// COW write-through: the successor with one field replaced. The host\n" +
    "/// needs it when a path writes THROUGH this instance to a nested child.\n" +
    "impl \{trait_name} for \{t} with fn with_field(self, name, v) {\n" +
    "  match (name, v) {\n",
  )
  for f in def.fields {
    match from_guest_value(def, f.ty, values) {
      Some((pat, expr)) =>
        out.write_string(
          "    (\{quote(f.name)}, \{pat}) =>\n" +
          "      Some({ ..self, \{f.binding}: \{expr} } as &\{trait_name})\n",
        )
      // A field whose shape has no total decode from a boundary value is
      // left unwritable rather than given a lossy one: `none` means "not
      // supported", which the host handles, and a wrong write does not.
      None => ()
    }
  }
  out.write_string("    _ => None\n  }\n}\n\n")
  // -- to_json --------------------------------------------------------------
  out.write_string(
    "///|\n" +
    "/// The JSON projection the host uses for inspection and for hot-swap\n" +
    "/// migration — the only view it has of opaque guest state.\n" +
    "impl \{trait_name} for \{t} with fn to_json(self) {\n",
  )
  if def.fields.is_empty() {
    out.write_string("  \"{}\"\n}\n\n")
  } else {
    let parts = def.fields.map(f => {
      "\"\\\"\{f.name}\\\": \" + " + json_expr(def, f.ty, "self." + f.binding)
    })
    out.write_string(
      "  \"{\" + " + parts.join(" + \", \" + ") + " + \"}\"\n}\n\n",
    )
  }
  // -- seq_entries ----------------------------------------------------------
  // Only when the state is a single list: iterating an instance means
  // iterating the one sequence it stands for, and a state with two lists has
  // no such reading.
  let lists = def.fields.filter(f => f.ty is TList(_))
  if lists.length() == 1 && def.fields.length() == 1 {
    let f = lists[0]
    guard f.ty is TList(e)
    out.write_string(
      "///|\n" +
      "/// Ordered entries, so the host's `@each` can iterate this instance as\n" +
      "/// a sequence.\n" +
      "impl \{trait_name} for \{t} with fn seq_entries(self) {\n" +
      "  let out = []\n" +
      "  for i, v in self.\{f.binding} {\n" +
      "    out.push((i.to_string(), \{to_guest_value(def, e, "v", values)}))\n" +
      "  }\n" +
      "  Some(out)\n}\n\n",
    )
  }
  out.to_string()
}

///|
/// The MoonBit type a guest holds a field in.
fn guest_ty(def : StateDef, ty : StateTy) -> String {
  match ty {
    TBool => "Bool"
    TInt(..) => "Int"
    TFloat => "Double"
    TText => "String"
    TList(e) => "Array[" + guest_ty(def, e) + "]"
    TOption(e) => guest_ty(def, e) + "?"
    // A child instance crosses as the host-assigned token, never as a value.
    TComp(_) => "UInt64"
    // Anything else rides as its JSON text: the boundary has no shape for it
    // and a guest that needs one can parse it.
    _ => "String"
  }
}

///|
/// A guest field as a boundary value.
fn to_guest_value(
  def : StateDef,
  ty : StateTy,
  expr : String,
  values : String,
) -> String {
  match ty {
    TBool => "\{values}.Value::Boolean(\{expr})"
    TInt(..) => "\{values}.Value::Number(\{expr}.to_double())"
    TFloat => "\{values}.Value::Number(\{expr})"
    TText => "\{values}.Value::Text(\{expr})"
    TComp(_) => "\{values}.Value::Instance(\{expr})"
    TList(e) => {
      // Compounds travel as arena handles, so a list is built by pushing
      // into one the host owns.
      let push = to_guest_value(def, e, "x", values)
      "{ let h = \{values}.list_new(); for x in \{expr} { \{values}.list_push(h, \{push}) }; \{values}.Value::List(h) }"
    }
    TOption(e) =>
      "match \{expr} { Some(x) => \{to_guest_value(def, e, "x", values)}; None => \{values}.Value::Nil }"
    _ => "\{values}.from_json(\{expr})"
  }
}

///|
/// The pattern and expression that decode a boundary value back into a
/// field, or None when the shape has no total decode.
fn from_guest_value(
  def : StateDef,
  ty : StateTy,
  values : String,
) -> (String, String)? {
  let _ = def
  match ty {
    TBool => Some(("\{values}.Value::Boolean(b)", "b"))
    TInt(..) => Some(("\{values}.Value::Number(n)", "n.to_int()"))
    TFloat => Some(("\{values}.Value::Number(n)", "n"))
    TText => Some(("\{values}.Value::Text(s)", "s"))
    TComp(_) => Some(("\{values}.Value::Instance(h)", "h"))
    _ => None
  }
}

///|
/// A guest field as a fragment of the JSON projection.
fn json_expr(def : StateDef, ty : StateTy, expr : String) -> String {
  match ty {
    TBool | TInt(..) | TFloat => "\{expr}.to_string()"
    TText => "\"\\\"\" + \{expr} + \"\\\"\""
    TComp(_) => "\{expr}.to_string()"
    TList(e) =>
      "\"[\" + \{expr}.map(x => \{json_expr(def, e, "x")}).join(\", \") + \"]\""
    TOption(e) =>
      "(match \{expr} { Some(x) => \{json_expr(def, e, "x")}; None => \"null\" })"
    // Already JSON text in the guest's own representation.
    _ => expr
  }
}

///|
/// A double-quoted MoonBit string literal.
fn quote(s : String) -> String {
  let sb = StringBuilder::new()
  sb.write_char('"')
  for c in s.to_array() {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}
