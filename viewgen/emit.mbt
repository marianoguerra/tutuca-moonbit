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
/// One `$`-callable bucket builder: the user writes an exhaustive match over
/// the method enum, so a `$name` added to a view breaks the build until it is
/// answered.
fn emit_bucket(
  out : StringBuilder,
  type_name : String,
  fn_name : String,
  handler_type : String,
  doc : String,
  variants : Array[(String, String)],
) -> Unit {
  let all = variants.map(p => p.1).join(", ")
  out.write_string(
    "///|\n" +
    "/// \{doc}\n" +
    "/// Return None for a name another bucket serves, or one of the mutators\n" +
    "/// generated from the state's fields.\n" +
    "pub fn[S] \{fn_name}(\n" +
    "  f : (\{type_name}) -> (\{handler_type})?,\n" +
    ") -> Map[String, \{handler_type}] {\n" +
    "  let out : Map[String, \{handler_type}] = Map([])\n" +
    "  for m in ([\{all}] : Array[\{type_name}]) {\n" +
    "    match f(m) {\n" +
    "      Some(h) => out[m.name()] = h\n" +
    "      None => ()\n" +
    "    }\n" +
    "  }\n" +
    "  out\n" +
    "}\n\n",
  )
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
/// One render-time directive bucket: its name enum and its builder.
///
/// Nothing is emitted when the views name no handler for it, on the same rule
/// the `Method` enum follows — an empty enum is not a MoonBit type, and a
/// bucket with no names has nothing for an author to answer.
fn emit_alter_bucket(
  out : StringBuilder,
  t : String,
  v : String,
  names : Array[String],
  suffix : String,
  bucket : String,
  doc : String,
  handler_type : String,
  derives : String,
) -> Unit raise GenError {
  if names.is_empty() {
    return
  }
  let vs = variants_for(names)
  emit_name_enum(out, doc, "\{t}\{suffix}", "name", vs, derives)
  emit_bucket(
    out,
    "\{t}\{suffix}",
    "\{v}_\{bucket}",
    handler_type,
    "Build `\{bucket}~` from an exhaustive match over the names the views use.",
    vs,
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
  let view_variants = variants_for(views.views.map(view => view.name))
  emit_name_enum(
    out,
    "The views declared in \{source_file}.",
    "\{t}View",
    "name",
    view_variants,
    derives,
  )
  // The built views themselves live in the IR module as `<v>_views()`; the
  // per-view sources and styles are carried inside those @anode.View values,
  // so nothing here re-emits them.

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
    // `swap` is keyed by the INPUT names, not by `$name`: it answers an Input
    // dispatch ahead of `update`, and is what lets a handler replace this node
    // with another component's instance.
    emit_bucket(
      out,
      "\{t}Input",
      "\{v}_swap",
      "(S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?",
      "Build `swap~` from an exhaustive match over the `@on` names the views raise.",
      input_variants,
    )
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
    emit_bucket(
      out,
      "\{t}Method",
      "\{v}_compute",
      "(S, Array[@tutuca.Value]) -> @tutuca.Value",
      "Build `compute~` from an exhaustive match over the names the views call.",
      method_variants,
    )
  }

  // -- the render-time directives ------------------------------------------
  // One enum per bucket, not one for all four: each has its own handler
  // signature, so a single `Alter` type could not type any of them.
  emit_alter_bucket(
    out,
    t,
    v,
    surface.whens,
    "When",
    "when",
    "Every `@when` handler the views name.",
    "(S, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    v,
    surface.enriches,
    "Enrich",
    "enrich",
    "Every `@enrich-with` handler named INSIDE an `@each`.",
    "(S, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    v,
    surface.enrich_scopes,
    "EnrichScope",
    "enrich_scope",
    "Every `@enrich-with` handler named with no `@each` around it.",
    "(S) -> Map[String, @tutuca.Value]",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    v,
    surface.loop_withs,
    "LoopWith",
    "loop_with",
    "Every `@loop-with` handler the views name.",
    "(S, @tutuca.Value, @component.LoopCtx) -> @component.LoopWith",
    derives,
  )

  // -- fields --------------------------------------------------------------
  // Superseded by the schema. `<v>_fields` and `<v>_missing_fields` existed
  // because the generator could not check a field read: it listed the names
  // and left you to assert, in a test you had to remember to write, that the
  // state carried them. A schema-backed component checks every read at
  // generation time — under a loop as well as at the root, which the list
  // never covered — so emitting a weaker second check would only invite
  // someone to rely on it.
  if state is Some(def_) {
    emit_ids(t, surface, derives, out)
    // Last, because it names things every section above declares.
    emit_schema(t, name, def_, surface, views, inits, out)
    return
  }
  out.write_string(
    "///|\n" +
    "/// State fields the views read at a view's ROOT scope. Reads under an\n" +
    "/// @each, an @enrich-with, a push-view or an <x render> address the loop\n" +
    "/// item or the child component, not this state, so they are not listed.\n" +
    "pub let \{v}_fields : Array[String] = [" +
    surface.fields.map(quote).join(", ") +
    "]\n\n",
  )
  out.write_string(
    "///|\n" +
    "/// The fields in `\{v}_fields` that `s` does not carry — assert this is\n" +
    "/// empty in a test. Fields the component declares through `specs~` rather\n" +
    "/// than through its state struct go in `extra~`.\n" +
    "pub fn[S : ToJson] \{v}_missing_fields(\n" +
    "  s : S,\n" +
    "  extra? : Array[String] = [],\n" +
    ") -> Array[String] {\n" +
    "  let present : Map[String, Bool] = Map([])\n" +
    "  if s.to_json() is Object(o) {\n" +
    "    for k, _ in o {\n" +
    "      present[k] = true\n" +
    "    }\n" +
    "  }\n" +
    "  for k in extra {\n" +
    "    present[k] = true\n" +
    "  }\n" +
    "  \{v}_fields.filter(f => !present.contains(f))\n" +
    "}\n\n",
  )

  emit_ids(t, surface, derives, out)
}

///|
/// Constant `id` attributes as typed selectors, for tests.
fn emit_ids(
  t : String,
  surface : Surface,
  derives : String,
  out : StringBuilder,
) -> Unit raise GenError {
  if !surface.ids.is_empty() {
    let id_variants = variants_for(surface.ids)
    emit_name_enum(
      out,
      "Constant `id` attributes in the views — typed selectors for tests.",
      "\{t}Id",
      "id",
      id_variants,
      derives,
    )
    out.write_string(
      "///|\n" +
      "/// The `#id` CSS selector for this element.\n" +
      "pub fn \{t}Id::selector(self : \{t}Id) -> String {\n" +
      "  \"#\" + self.id()\n" +
      "}\n\n",
    )
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
