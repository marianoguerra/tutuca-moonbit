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
  emit_zero(t, def, out)
  emit_inits(t, v, def, inits, out)
  emit_codec(t, def, out)
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
  // The NAMES go in `SchemaInfo.init_names` and nowhere else: a second `pub let`
  // saying the same thing could only be read by code that already knows this
  // component's module, while the descriptor is reachable from a bare Value.
  out.write_string(
    "///|\n" +
    "/// A named initial state as component arguments — what a ModuleDef\n" +
    "/// example takes. None when no fixture has that name.\n" +
    "///\n" +
    "/// This is the public face of the fixtures: they return the private state\n" +
    "/// type, so they cannot be public themselves, and a storybook needs the\n" +
    "/// encoded form anyway.\n" +
    "pub fn \{v}_init_args(name : String) -> Map[String, @tutuca.Value]? {\n" +
    "  match name {\n",
  )
  for st in inits {
    out.write_string(
      "    \{quote(st.name)} => Some(@component.Fields::encode(\{t}State::\{st.ident}()))\n",
    )
  }
  out.write_string("    _ => None\n  }\n}\n\n")
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
        out.write_string("} derive(\{derives})\n\n")
      }
      UEnum(cases) => {
        out.write_string("///|\n")
        emit_doc(ty.doc, "The `\{ty.wit_name}` enum.", out)
        out.write_string("pub(all) enum \{ty.name} {\n")
        for c in cases {
          out.write_string("  \{c.1}\n")
        }
        out.write_string("} derive(\{derives})\n\n")
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
        out.write_string("} derive(\{derives})\n\n")
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
    out.write_string("pub(all) struct \{t}State {}\n\n")
    return
  }
  out.write_string("pub(all) struct \{t}State {\n")
  for f in carried {
    out.write_string("  \{f.binding} : \{def.moonbit_ty(f.ty)}\n")
  }
  // No derive, and none needed for a keyword binding either. The view reads
  // `.type` and the fields map carries "type"; it used to be a
  // `derive(ToJson(fields(type_(rename="type"))))` that put the name back,
  // and now it is the codec, which keys by the runtime name directly.
  out.write_string("}\n\n")
}

///|
fn emit_zero(t : String, def : @statedef.StateDef, out : StringBuilder) -> Unit {
  out.write_string(
    "///|\n" +
    "/// The zero state: every field at its type's empty value.\n" +
    "///\n" +
    "/// WIT declares no defaults — a default is a value, not a type — so this\n" +
    "/// is type-directed, and `init` spreads it to name only what differs:\n" +
    "///\n" +
    "///   init={ ..\{t}State::zero(), label: \"Counter\" }\n" +
    // `pub`, like the `pub(all)` struct it returns. It used to be private with a
    // public `<v>_zero_args()` wrapper beside it, whose only real job was to keep
    // this from reading as unused in a file with no generated `component()`
    // wrapper to default `init~` from. Making the thing itself public says that
    // directly, and the encoded form nobody asked for goes away.
    "pub fn \{t}State::zero() -> \{t}State {\n",
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
}

// There is no `<T>Field` enum and no `<v>_field_names`. Both restated
// `SchemaInfo.fields`, which carries the same names WITH their declared kind
// and type — and carries them where a holder of a bare `@tutuca.Value` can
// read them, which is what the inspector and the state editor actually do. A
// typed field enum can only be read by code that already knows the component's
// type, and such code can spell the field name directly.

///|
/// The static description an inspector reads instead of reflecting.
///
/// Everything here is known at generation time and none of it survives into
/// the runtime descriptor on its own. The `inputs` list is the point: the
/// names `update` answers are one opaque pattern match at runtime, so
/// introspection could only ever report THAT an update exists.
fn emit_schema(
  t : String,
  name : String,
  def : @statedef.StateDef,
  surface : Surface,
  views : ViewSet,
  inits : Array[@statedef.InitState],
  out : StringBuilder,
) -> Unit {
  // Written through `SchemaInfo::new` / `FieldInfo::new` rather than as record
  // literals. The trimming constructors exist for exactly this, and a channel
  // a component does not use now costs no line at all instead of a `[]` — the
  // difference between a descriptor that STATES ten things and one where the
  // two or three real answers are buried among seven empties.
  let out_channel = (label : String, xs : Array[String]) => {
    if xs.is_empty() {
      ""
    } else {
      "    \{label}=[" + xs.map(quote).join(", ") + "],\n"
    }
  }
  out.write_string(
    "///|\n" +
    "/// What this component's schema declares, for `schema~`.\n" +
    "///\n" +
    "/// This is the only thing consulted for a field's KIND — there is no\n" +
    "/// inference off the init value behind it — and it is what an instance\n" +
    "/// answers `obj_schema()` with, so a holder of a bare `@tutuca.Value`\n" +
    "/// can name these fields without a component registry.\n" +
    "impl @component.Fields for \{t}State with fn schema() {\n" +
    "  @component.SchemaInfo::new(\n" +
    // Empty for a schema-only file: there is no generated wrapper there, so
    // the author's own `component(name~ = ...)` is the authority and
    // `new_component` stamps it in. Stating a guess here would beat it.
    (if name == "" { "" } else { "    name=\{quote(name)},\n" }) +
    "    fingerprint=\{quote(@statedef.fingerprint([def]))},\n",
  )
  if !def.fields.is_empty() {
    out.write_string("    fields=[\n")
    for f in def.fields {
      // One argument, where there were five. The WIT spelling, the runtime
      // kind, a collection's element type, a slot's component and a closed
      // set's members are all questions the type answers, so writing them
      // out separately only created five chances to disagree with it.
      out.write_string(
        "      @component.FieldInfo::new(\{quote(f.name)}, \{def.ty_info_src(f.ty)}),\n",
      )
    }
    out.write_string("    ],\n")
  }
  out.write_string(out_channel("inputs", surface.inputs.map(i => i.name)))
  out.write_string(out_channel("receives", def.receive.map(m => m.name)))
  out.write_string(out_channel("bubbles", def.bubble.map(m => m.name)))
  out.write_string(out_channel("responses", def.response.map(m => m.name)))
  out.write_string(out_channel("methods", declared_methods(surface, Some(def))))
  out.write_string(out_channel("ids", surface.ids))
  out.write_string(out_channel("view_names", views.views.map(vw => vw.name)))
  out.write_string(out_channel("init_names", inits.map(st => st.name)))
  out.write_string("  )\n}\n\n")
}
