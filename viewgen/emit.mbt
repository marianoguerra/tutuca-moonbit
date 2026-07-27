// Emitting the generated MoonBit module.
//
// The output is valid but UNFORMATTED MoonBit: `moon fmt` owns the layout,
// and the `gen-views` dev task runs it right after generating. Emitting
// fmt-identical text would mean reimplementing its width-based line breaking.
// What this file does control is structure — one `///|` block per
// declaration, and multi-line view sources as `#|` raw-string blocks (a view
// is full of double quotes; escaping them into a normal literal would make
// the generated file unreadable and diff-noisy).
//
// Sections are skipped entirely when empty, because MoonBit has no empty
// enum: a file with no `$method` calls emits no Method type at all.

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
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A `pub let` holding view or style source. Multi-line text becomes a `#|`
/// block; empty or single-line text stays a quoted literal.
fn emit_string_let(
  out : StringBuilder,
  doc : String,
  name : String,
  text : String,
) -> Unit {
  out.write_string("///|\n/// \{doc}\n")
  if text.contains("\n") {
    out.write_string("pub let \{name} : String =\n")
    for line in text.split("\n") {
      out.write_string("  #|\{line}\n")
    }
  } else {
    out.write_string("pub let \{name} : String = \{quote(text)}\n")
  }
  out.write_string("\n")
}

///|
/// `pub enum <Type> { … }` plus a `name()` giving the source spelling back.
fn emit_name_enum(
  out : StringBuilder,
  doc : String,
  type_name : String,
  accessor : String,
  variants : Array[(String, String)],
  derives : String,
) -> Unit {
  out.write_string("///|\n/// \{doc}\npub(all) enum \{type_name} {\n")
  for pair in variants {
    out.write_string("  \{pair.1}\n")
  }
  out.write_string("} derive(\{derives})\n\n")
  out.write_string(
    "///|\npub fn \{type_name}::\{accessor}(self : \{type_name}) -> String {\n  match self {\n",
  )
  for pair in variants {
    out.write_string("    \{pair.1} => \{quote(pair.0)}\n")
  }
  out.write_string("  }\n}\n\n")
}

///|
fn arg_type_name(t : ArgType) -> String {
  match t {
    VDouble => "Double"
    VString => "String"
    VBool => "Bool"
    VValue => "@tutuca.Value"
  }
}

///|
/// The @core.Value pattern that binds a payload of this type.
fn arg_pattern(t : ArgType, binder : String) -> String {
  match t {
    VDouble => "Num(\{binder})"
    VString => "Str(\{binder})"
    VBool => "Bool(\{binder})"
    VValue => binder
  }
}

///|
/// The `Msg` variant payload for one input, and the match arm that decodes
/// it. `args: None` means the call sites disagreed on arity, so the variant
/// carries the raw argument list instead.
fn emit_msg_variant(
  out : StringBuilder,
  sig : InputSig,
  variant : String,
) -> Unit {
  let sites = sig.sites.join(", ")
  out.write_string("  /// `\{sites}=\"\{sig.name} …\"`\n")
  match sig.args {
    None => out.write_string("  \{variant}(Array[@tutuca.Value])\n")
    Some(types) =>
      if types.is_empty() {
        out.write_string("  \{variant}\n")
      } else {
        out.write_string(
          "  \{variant}(" + types.map(arg_type_name).join(", ") + ")\n",
        )
      }
  }
}

///|
fn emit_msg_arm(out : StringBuilder, sig : InputSig, variant : String) -> Unit {
  match sig.args {
    None =>
      out.write_string("    (\{quote(sig.name)}, _) => \{variant}(args)\n")
    Some(types) =>
      if types.is_empty() {
        out.write_string("    (\{quote(sig.name)}, []) => \{variant}\n")
      } else {
        let binders = types.mapi((i, _) => "a\{i}")
        let pats = types.mapi((i, t) => arg_pattern(t, binders[i]))
        out.write_string(
          "    (\{quote(sig.name)}, [" +
          pats.join(", ") +
          "]) => \{variant}(" +
          binders.join(", ") +
          ")\n",
        )
      }
  }
}

///|
/// Every `$`-callable this component answers: the ones its views call, and the
/// ones its state block declares as `func`. Sorted and de-duplicated, so a
/// method that is both called and declared is one enum case.
fn declared_methods(
  surface : Surface,
  state : @statedef.StateDef?,
) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  let add = (n : String) => {
    if !seen.contains(n) {
      seen[n] = ()
      out.push(n)
    }
  }
  for m in surface.methods {
    add(m)
  }
  match state {
    Some(def) =>
      for m in def.methods {
        add(m.name)
      }
    None => ()
  }
  out.sort_by((a, b) => a.lexical_compare(b))
  out
}

///|
/// One render-time directive bucket: the enum naming its handlers.
///
/// Nothing is emitted when the views name no handler for it, on the same rule
/// the `Method` enum follows — an empty enum is not a MoonBit type, and a
/// bucket with no names has nothing for an author to answer.
///
/// The enum is all that is emitted. Turning the author's match over it into
/// the `Map[String, H]` that `component()` takes is `@component.build_bucket`,
/// which the generated wrapper calls with the case list — one generic function
/// instead of the identical 14-line loop this used to write out per component
/// per bucket, 143 times across the corpus.
fn emit_alter_bucket(
  out : StringBuilder,
  t : String,
  names : Array[String],
  suffix : String,
  doc : String,
  derives : String,
) -> Unit raise GenError {
  if names.is_empty() {
    return
  }
  emit_name_enum(
    out,
    doc,
    "\{t}\{suffix}",
    "name",
    variants_for(names),
    derives,
  )
}

///|
/// One component's section of the generated types module.
fn emit_component(
  name : String,
  source_file : String,
  views : ViewSet,
  surface : Surface,
  state : @statedef.StateDef?,
  inits : Array[@statedef.InitState],
  debug_derive : Bool,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(name)
  let v = value_prefix(name)
  // The playground compiles the generated module inside a package with no
  // moon.pkg to import moonbitlang/core/debug from, so it asks for Eq alone.
  let derives = if debug_derive { "Eq, @debug.Debug" } else { "Eq" }

  // -- state ---------------------------------------------------------------
  // First, because everything below may refer to its types.
  if state is Some(def) {
    emit_state(t, v, def, inits, derives, out)
  }

  // -- views ---------------------------------------------------------------
  // The built views themselves live in the IR module as `<v>_views()`; the
  // per-view sources and styles are carried inside those @anode.View values,
  // so nothing here re-emits them. The view NAMES are declared metadata and
  // live in `SchemaInfo.view_names`, which a holder of a bare @tutuca.Value
  // can read — a `<T>View` enum could only be read by code that already knows
  // the component's type, which is code that can spell the name anyway.

  // -- component-level styles ----------------------------------------------
  // Per-view style rides inside each View; only the two component-wide styles
  // are separate arguments to component().
  emit_string_let(
    out,
    "The file-level style — pass as `common_style~`.",
    "\{v}_common_style",
    views.common_style,
  )
  emit_string_let(
    out,
    "The `data-global` style — pass as `global_style~`.",
    "\{v}_global_style",
    views.global_style,
  )

  // -- inputs --------------------------------------------------------------
  if !surface.inputs.is_empty() {
    let input_variants = variants_for(surface.inputs.map(i => i.name))
    emit_name_enum(
      out,
      "Every bare `@on` handler name the views reference.",
      "\{t}Input",
      "name",
      input_variants,
      derives,
    )
    out.write_string(
      "///|\npub fn \{t}Input::parse(s : String) -> \{t}Input? {\n  match s {\n",
    )
    for pair in input_variants {
      out.write_string("    \{quote(pair.0)} => Some(\{pair.1})\n")
    }
    out.write_string("    _ => None\n  }\n}\n\n")

    // The typed decode: this is the point of the whole generator.
    out.write_string(
      "///|\n" +
      "/// The Input arm of @component.Dispatch, decoded. Payload types are\n" +
      "/// inferred from the argument shapes written at the call sites, so a\n" +
      "/// handler added to \{source_file} breaks every `match` over this type\n" +
      "/// until it is handled.\n" +
      "pub(all) enum \{t}Msg {\n",
    )
    for i, sig in surface.inputs {
      emit_msg_variant(out, sig, input_variants[i].1)
    }
    out.write_string(
      "  /// An Input dispatch the views do not declare, or a declared name\n" +
      "  /// whose runtime arguments did not match the inferred shape.\n" +
      "  Unknown(String, Array[@tutuca.Value])\n" +
      // No derives: @tutuca.Value carries Fn and &Obj, so it is neither Eq
      // nor Debug, and a payload of it would make the derive fail.
      "}\n\n",
    )
    out.write_string(
      "///|\n" +
      "/// None for Receive / Bubble / Response — those names are raised by\n" +
      "/// component code, never written in a view, so the views cannot type them.\n" +
      "pub fn \{t}Msg::from_dispatch(d : @component.Dispatch) -> \{t}Msg? {\n" +
      "  guard d is Input(name, args) else { return None }\n" +
      "  Some(\n" +
      "    match (name, args) {\n",
    )
    for i, sig in surface.inputs {
      out.write_string("  ")
      emit_msg_arm(out, sig, input_variants[i].1)
    }
    out.write_string("      _ => Unknown(name, args)\n    },\n  )\n}\n\n")
  }

  // -- $-callables ---------------------------------------------------------
  // The views' `$name` calls PLUS the `func` declarations in the state block.
  // A method a parent calls on this component appears in neither its views nor
  // its update, so the schema is the only place it can be named — and without a
  // case for it, the match the author writes could not answer it.
  let all_methods = declared_methods(surface, state)
  if !all_methods.is_empty() {
    let method_variants = variants_for(all_methods)
    emit_name_enum(
      out,
      "Every `$name` the views call.",
      "\{t}Method",
      "name",
      method_variants,
      derives,
    )
    // No `<v>_mutate`: the bucket is gone. A `$name` only ever appears in a
    // value position now, where `compute` and `swap` are what answer it —
    // an event handler is a bare name and belongs to `update`.
  }

  // -- the render-time directives ------------------------------------------
  // One enum per bucket, not one for all four: each has its own handler
  // signature, so a single `Alter` type could not type any of them.
  emit_alter_bucket(
    out,
    t,
    surface.whens,
    "When",
    "Every `@when` handler the views name.",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    surface.enriches,
    "Enrich",
    "Every `@enrich-with` handler named INSIDE an `@each`.",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    surface.enrich_scopes,
    "EnrichScope",
    "Every `@enrich-with` handler named with no `@each` around it.",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    surface.loop_withs,
    "LoopWith",
    "Every `@loop-with` handler the views name.",
    derives,
  )

  // -- the declared description --------------------------------------------
  // Last, because it names things every section above declares.
  //
  // Two things used to be emitted here as well, and both were weaker restatements
  // of what this descriptor already carries. `<v>_fields` / `<v>_missing_fields`
  // existed because the generator could not check a field read: they listed the
  // names and left you to assert, in a test you had to remember to write, that
  // the state carried them — and only ever covered a view's ROOT scope. A
  // schema-backed component checks every read at generation time, loop bodies
  // included. `<T>Id` turned the same `surface.ids` that `SchemaInfo.ids` carries
  // into an enum that nothing read.
  if state is Some(def_) {
    emit_schema(t, name, def_, surface, views, inits, out)
  }
}

///|
/// The generated types module for a whole view file: one section per
/// component it declares.
pub fn emit_module(
  name : String,
  source_file : String,
  file : ViewFile,
  debug_derive? : Bool = true,
) -> String raise GenError {
  let out = StringBuilder::new()
  out.write_string(
    "// GENERATED by `tutuca gen-views` from \{source_file} — DO NOT EDIT.\n" +
    "// Regenerate with:\n" +
    "//\n" +
    "//   tutuca gen-views \{source_file} --name \{name} --out <dir>\n" +
    "//\n" +
    "// The package this file lives in must import:\n" +
    "//   \"marianoguerra/tutuca/core\" @tutuca, \"marianoguerra/tutuca/component\"" +
    (if debug_derive { ",\n//   \"moonbitlang/core/debug\"\n" } else { "\n" }) +
    "\n",
  )
  // A schema entry is matched to the component of the same name. An entry
  // that matches nothing is a spelling difference between the block and the
  // templates, and silently generating no state for it would look exactly
  // like the schema not working.
  let declared = declared_components(file, name)
  // A schema entry with no matching template declares state for a component
  // whose views are built in MoonBit. That is legitimate — and it may sit
  // alongside components that DO have templates, because one file often
  // holds both. It is also what a mistyped interface name looks like, so
  // the CLI reports it as a diagnostic (cli/gen_views.mbt) rather than
  // generating in silence.
  for def in file.state {
    if !declared.contains(def.component) {
      emit_state_only(def, file, debug_derive, out)
    }
  }
  for comp in file.components {
    let cname = comp.component_name(name)
    let surface = view_surface(comp.views, macros=file.macros)
    let state = state_for(file, cname)
    let inits = file.init.filter(p => p.0 == cname).map(p => p.1)
    // Checked before emitting: a view that reads a field the schema does not
    // declare would otherwise emit a module that compiles and renders null.
    if state is Some(def) {
      check_views(comp.views, file.macros, def)
    }
    emit_component(
      cname, source_file, comp, surface, state, inits, debug_derive, out,
    )
  }
  out.to_string()
}

///|
/// The component names this file gives views to.
pub fn declared_components(file : ViewFile, name : String) -> Array[String] {
  let out : Array[String] = []
  for comp in file.components {
    out.push(comp.component_name(name))
  }
  out
}

///|
/// The state half alone, for a component whose views are built at runtime.
///
/// No view surface to extract and nothing to check the schema against — the
/// views this state belongs to are assembled in MoonBit, where the compiler
/// checks them instead.
fn emit_state_only(
  def : @statedef.StateDef,
  file : ViewFile,
  debug_derive : Bool,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(def.component)
  let v = value_prefix(def.component)
  let derives = if debug_derive { "Eq, @debug.Debug" } else { "Eq" }
  let inits = file.init.filter(p => p.0 == def.component).map(p => p.1)
  emit_state(t, v, def, inits, derives, out)
  // The schema too. Its view-derived lists — inputs, methods, ids, view names
  // — come out EMPTY, and that is the honest reading: this file declares the
  // component's data and no views, so there is no `@on` handler or `$name` in
  // it to have found. The alternative was emitting no schema at all, which
  // left `component()` with nothing to be told and the runtime guessing field
  // kinds from the init value. A partial declaration still beats a
  // reconstruction, and the missing half is recovered by moving the templates
  // into the view file — which is the incentive.
  let empty_surface : Surface = {
    inputs: [],
    methods: [],
    fields: [],
    ids: [],
    whens: [],
    enriches: [],
    enrich_scopes: [],
    loop_withs: [],
  }
  let no_views : ViewSet = {
    name: def.component,
    views: [],
    common_style: "",
    global_style: "",
  }
  emit_schema(t, "", def, empty_surface, no_views, inits, out)
}

///|
/// The schema entry for a component, or None when the file declares none.
fn state_for(file : ViewFile, comp : String) -> @statedef.StateDef? {
  for def in file.state {
    if def.component == comp {
      return Some(def)
    }
  }
  None
}

///|
pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError {
  emit_module(name, source_file, split_file(source))
}
