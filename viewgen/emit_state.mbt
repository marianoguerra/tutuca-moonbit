// Emitting the state half of the generated module.
//
// This is the section that replaces hand-written code rather than describing
// it: the struct the author used to write, its derives, the `specs~` map
// they used to keep in sync by hand, and a zero value so `init` only names
// what actually differs from it.
//
// Everything here is emitted `priv`. Generated and hand-written .mbt files
// share a package, so the update function reaches the type without it
// entering pkg.generated.mbti — a component's state is nobody else's
// business. `pub` on demand is Stage 5's problem (dyncomp guests cross a
// package boundary), not this file's.

///|
/// The state struct, its zero, the field descriptor table and the specs map.
///
/// `def` is the schema for THIS component. A file whose block declares no
/// interface for a component emits none of this, which is what lets the view
/// files migrate one at a time.
fn emit_state(
  t : String,
  v : String,
  def : @statedef.StateDef,
  inits : Array[@statedef.InitState],
  derives : String,
  out : StringBuilder,
) -> Unit raise GenError {
  emit_user_types(def, derives, out)
  emit_state_struct(t, def, out)
  emit_zero(t, v, def, out)
  emit_field_enum(t, v, def, derives, out)
  emit_fingerprint(v, def, out)
  emit_inits(t, v, def, inits, out)
  emit_codec(t, v, def, out)
  emit_msgs(t, def, out)
}

///|
/// The named initial states from the init block.
///
/// Each spreads over `zero()` and names only what it sets, so a fixture stays
/// a statement of what is INTERESTING about it rather than a full record
/// that has to be edited every time the schema grows a field.
///
/// The fixtures themselves are package-private, because they return the
/// private state type. They are reachable from `<v>_init_args`, which is
/// public and returns the encoded form a ModuleDef example takes — so the
/// generated file has no unused declaration, and a storybook gets its
/// example arguments from the same checked source the component inits from.
fn emit_inits(
  t : String,
  v : String,
  def : @statedef.StateDef,
  inits : Array[@statedef.InitState],
  out : StringBuilder,
) -> Unit {
  if inits.is_empty() {
    return
  }
  for st in inits {
    out.write_string(
      "///|\n" +
      "/// The `\{st.name}` initial state, from the init block. Checked against\n" +
      "/// the schema at generation time, so a field the schema dropped fails\n" +
      "/// the build instead of being coerced away at runtime.\n" +
      "fn \{t}State::\{st.ident}() -> \{t}State {\n",
    )
    if st.fields.is_empty() {
      out.write_string("  \{t}State::zero()\n}\n\n")
    } else {
      // A fixture that sets EVERY field needs no spread — and MoonBit warns
      // about one that has no effect, which a generated file must not trip.
      let full = st.fields.length() == def.fields.length()
      out.write_string(
        if full {
          "  \{t}State::{\n"
        } else {
          "  {\n    ..\{t}State::zero(),\n"
        },
      )
      for f in st.fields {
        out.write_string("    \{f.0}: \{f.1},\n")
      }
      out.write_string("  }\n}\n\n")
    }
  }
  out.write_string(
    "///|\n" +
    "/// Every named initial state, in the order the init block declares them.\n" +
    "pub let \{v}_init_names : Array[String] = [" +
    inits.map(st => quote(st.name)).join(", ") +
    "]\n\n",
  )
  out.write_string(
    "///|\n" +
    "/// A named initial state as component arguments — what a ModuleDef\n" +
    "/// example takes. None when no fixture has that name.\n" +
    "///\n" +
    "/// This is the public face of the fixtures: they return the private state\n" +
    "/// type, so they cannot be public themselves, and a storybook needs the\n" +
    "/// encoded form anyway.\n" +
    "pub fn \{v}_init_args(name : String) -> Map[String, @tutuca.Value]? {\n" +
    "  let j = match name {\n",
  )
  for st in inits {
    out.write_string(
      // `ToJson::to_json(x)` rather than `x.to_json()`: the implicit method
      // promotion from a derived impl is deprecated, and a generated file
      // must not be the thing that warns.
      "    \{quote(st.name)} => ToJson::to_json(\{t}State::\{st.ident}())\n",
    )
  }
  out.write_string(
    "    _ => return None\n" +
    "  }\n" +
    "  match @tutuca.Value::from_json(j) {\n" +
    "    Map(m) => Some(m)\n" +
    "    _ => None\n" +
    "  }\n}\n\n",
  )
}

///|
/// The schema's structural fingerprint.
///
/// Over shape, not over source text: reindenting the block leaves it alone,
/// renaming a field changes it. A hot swap or a stored state that crosses a
/// change in this value cannot be reinterpreted, only migrated.
fn emit_fingerprint(
  v : String,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "///|\n" +
    "/// The structural fingerprint of this component's schema. Changes when\n" +
    "/// the SHAPE changes — a renamed or retyped field, a new message case —\n" +
    "/// and not when the block is merely reformatted.\n" +
    "pub let \{v}_schema_fingerprint : String = \{quote(@statedef.fingerprint([def]))}\n\n",
  )
}

///|
/// The named `record`/`enum`/`variant` types the state mentions, in the
/// stable order statedef sorted them into.
///
/// `pub(all)`, like every other piece of generated vocabulary (`<T>Field`,
/// `<T>Msg`, `<T>View`): these are the names an `update` pattern-matches and a
/// test constructs. Private, their `Eq`/`Debug` derives also read as unused to
/// a non-test build, which is a warning for something the tests do use.
fn emit_user_types(
  def : @statedef.StateDef,
  derives : String,
  out : StringBuilder,
) -> Unit {
  for ty in def.types {
    match ty.kind {
      URecord(fields) => {
        if fields.is_empty() {
          continue // a transparent alias: it named a marker, nothing more
        }
        out.write_string("///|\n")
        emit_doc(ty.doc, "The `\{ty.wit_name}` record.", out)
        out.write_string("pub(all) struct \{ty.name} {\n")
        for f in fields {
          out.write_string("  \{f.binding} : \{def.moonbit_ty(f.ty)}\n")
        }
        out.write_string("} derive(ToJson, FromJson, \{derives})\n\n")
      }
      UEnum(cases) => {
        out.write_string("///|\n")
        emit_doc(ty.doc, "The `\{ty.wit_name}` enum.", out)
        out.write_string("pub(all) enum \{ty.name} {\n")
        for c in cases {
          out.write_string("  \{c.1}\n")
        }
        out.write_string("} derive(ToJson, FromJson, \{derives})\n\n")
      }
      UVariant(cases) => {
        out.write_string("///|\n")
        emit_doc(ty.doc, "The `\{ty.wit_name}` variant.", out)
        out.write_string("pub(all) enum \{ty.name} {\n")
        for c in cases {
          if c.payload.is_empty() {
            out.write_string("  \{c.variant}\n")
          } else {
            let ps = c.payload.map(p => def.moonbit_ty(p)).join(", ")
            out.write_string("  \{c.variant}(\{ps})\n")
          }
        }
        out.write_string("} derive(ToJson, FromJson, \{derives})\n\n")
      }
      // A `flags` set is Map-backed at runtime like any other set, so it
      // contributes no MoonBit type — only the member list, which the specs
      // map below carries as the set's default membership.
      UFlags(_) => ()
    }
  }
}

///|
fn emit_doc(doc : String?, fallback : String, out : StringBuilder) -> Unit {
  match doc {
    Some(d) =>
      for line in d.split("\n") {
        out.write_string("/// \{line}\n")
      }
    None => out.write_string("/// \{fallback}\n")
  }
}

///|
fn emit_state_struct(
  t : String,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  out.write_string("///|\n")
  emit_doc(def.doc, "The state of the \{t} component.", out)
  out.write_string(
    "///\n" +
    "/// Declared as `interface \{def.wit_name}` in the state block. Adding a\n" +
    "/// field there adds it here, so a view that reads it type-checks and one\n" +
    "/// that reads a name this struct lacks fails generation.\n",
  )
  // Child slots are declared in the schema but do NOT become struct fields:
  // the runtime creates them from the `specs~` entry through the
  // registration scope, which is why they had to live out-of-band before.
  let carried = def.fields.filter(f => f.ty.in_struct())
  if carried.is_empty() {
    // MoonBit has no empty struct body on one line worth breaking; a state
    // with no fields is common (a toolbar is behaviour, not data).
    out.write_string("priv struct \{t}State {} derive(ToJson, FromJson)\n\n")
    return
  }
  out.write_string("priv struct \{t}State {\n")
  for f in carried {
    out.write_string("  \{f.binding} : \{def.moonbit_ty(f.ty)}\n")
  }
  // A MoonBit keyword binding must not change the JSON name: the view reads
  // `.type` and the wire carries "type", so it is the binding that bends and
  // the derive that puts the name back.
  let renamed = carried.filter(f => f.binding != f.name)
  if renamed.is_empty() {
    out.write_string("} derive(ToJson, FromJson)\n\n")
  } else {
    let fs = renamed.map(f => "\{f.binding}(rename=\"\{f.name}\")").join(", ")
    out.write_string(
      "} derive(ToJson(fields(\{fs})), FromJson(fields(\{fs})))\n\n",
    )
  }
}

///|
fn emit_zero(
  t : String,
  v : String,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "///|\n" +
    "/// The zero state: every field at its type's empty value.\n" +
    "///\n" +
    "/// WIT declares no defaults — a default is a value, not a type — so this\n" +
    "/// is type-directed, and `init` spreads it to name only what differs:\n" +
    "///\n" +
    "///   init={ ..\{t}State::zero(), label: \"Counter\" }\n" +
    // Package-private, like the struct it returns: a public function may not
    // depend on a private type, and the state is nobody else's business.
    "fn \{t}State::zero() -> \{t}State {\n",
  )
  let carried = def.fields.filter(f => f.ty.in_struct())
  if carried.is_empty() {
    out.write_string("  \{t}State::{  }\n}\n\n")
  } else {
    out.write_string("  \{t}State::{\n")
    for f in carried {
      out.write_string("    \{f.binding}: \{def.zero_expr(f.ty)},\n")
    }
    out.write_string("  }\n}\n\n")
  }
  // `zero` is package-private, like the struct it returns, so a component
  // that seeds from a literal would leave it unused — and a generated file
  // must not be the thing that warns. This is its public face, and it is
  // what a storybook example's default arguments are anyway.
  out.write_string(
    "///|\n" +
    "/// The zero state as component arguments — the default a ModuleDef\n" +
    "/// example takes when it sets nothing of its own.\n" +
    "pub fn \{v}_zero_args() -> Map[String, @tutuca.Value] {\n" +
    "  match @tutuca.Value::from_json(ToJson::to_json(\{t}State::zero())) {\n" +
    "    Map(m) => m\n" +
    "    _ => Map([])\n" +
    "  }\n}\n\n",
  )
}

///|
/// The field descriptor table: every field as a typed name, with the kind
/// the runtime will give it.
fn emit_field_enum(
  t : String,
  v : String,
  def : @statedef.StateDef,
  derives : String,
  out : StringBuilder,
) -> Unit raise GenError {
  if def.fields.is_empty() {
    return
  }
  let variants = variants_for(def.fields.map(f => f.name))
  emit_name_enum(
    out,
    "Every field the \{t} state declares — typed field names for tests and inspectors.",
    "\{t}Field",
    "name",
    variants,
    derives,
  )
  out.write_string(
    "///|\n" +
    "/// The runtime kind this field carries. Declared, not inferred: the old\n" +
    "/// `FieldSpec::of_default` had to guess FInt from whether the seed value\n" +
    "/// happened to be integral.\n" +
    "pub fn \{t}Field::kind(self : \{t}Field) -> @component.FieldKind {\n" +
    "  match self {\n",
  )
  for i, f in def.fields {
    out.write_string("    \{variants[i].1} => \{f.ty.field_kind_src()}\n")
  }
  out.write_string("  }\n}\n\n")
  out.write_string(
    "///|\n" +
    "/// Every field, in declaration order.\n" +
    "pub let \{v}_field_names : Array[String] = [" +
    def.fields.map(f => quote(f.name)).join(", ") +
    "]\n\n",
  )
}

///|
/// The static description an inspector reads instead of reflecting.
///
/// Everything here is known at generation time and none of it survives into
/// the runtime descriptor on its own. The `inputs` list is the point: the
/// names `update` answers are one opaque pattern match at runtime, so
/// introspection could only ever report THAT an update exists.
fn emit_schema(
  t : String,
  v : String,
  def : @statedef.StateDef,
  surface : Surface,
  views : ViewSet,
  inits : Array[@statedef.InitState],
  out : StringBuilder,
) -> Unit {
  let strs = (xs : Array[String]) => "[" + xs.map(quote).join(", ") + "]"
  out.write_string(
    "///|\n" +
    "/// What this component's schema declares, for `schema~`.\n" +
    "///\n" +
    "/// Passing it to `component` also stops the runtime inferring field\n" +
    "/// kinds from the init value — the schema states them.\n" +
    "pub fn \{v}_schema() -> @component.SchemaInfo {\n" +
    "  {\n" +
    "    fingerprint: \{quote(@statedef.fingerprint([def]))},\n" +
    "    fields: [\n",
  )
  for f in def.fields {
    let elem = match f.ty.elem() {
      Some(e) => "Some(\{quote(e.show_wit())})"
      None => "None"
    }
    let slot = match f.ty {
      TComp(Some(c)) => "Some(\{quote(c)})"
      TComp(None) => "Some(\"\")"
      _ => "None"
    }
    // Only a `flags` set has declared members; an open `text-set` does not.
    let members = match f.ty {
      TFlags(n) =>
        match def.user_ty(n) {
          Some({ kind: UFlags(ms), .. }) => ms.map(m => quote(m.1)).join(", ")
          _ => ""
        }
      _ => ""
    }
    out.write_string(
      "      {\n" +
      "        name: \{quote(f.name)},\n" +
      "        ty: \{quote(f.ty.show_wit())},\n" +
      "        kind: \{f.ty.field_kind_src()},\n" +
      "        elem: \{elem},\n" +
      "        slot: \{slot},\n" +
      "        members: [\{members}],\n" +
      "      },\n",
    )
  }
  out.write_string(
    "    ],\n" +
    "    inputs: \{strs(surface.inputs.map(i => i.name))},\n" +
    "    receives: \{strs(def.receive.map(m => m.name))},\n" +
    "    bubbles: \{strs(def.bubble.map(m => m.name))},\n" +
    "    responses: \{strs(def.response.map(m => m.name))},\n" +
    "    methods: \{strs(declared_methods(surface, Some(def)))},\n" +
    "    ids: \{strs(surface.ids)},\n" +
    "    view_names: \{strs(views.views.map(vw => vw.name))},\n" +
    "    init_names: \{strs(inits.map(st => st.name))},\n" +
    "  }\n}\n\n",
  )
  t |> ignore
}
