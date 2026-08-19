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
/// A double-quoted MoonBit string literal. `@statedef.quote`, reached through
/// it so the generators cannot drift.
fn quote(s : String) -> String {
  @statedef.quote(s)
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
/// The names the script block ANSWERS, by bucket — what the author-facing
/// enums are trimmed against.
///
/// A name answered here is routed BEFORE the author's match is consulted:
/// `update` is composed behind the block's transition, and each bucket's
/// generated router is asked before the author's function. So a variant for an
/// answered name could not be reached. Leaving it in would cost twice — the
/// author writes an arm that cannot run, and an author who writes a REAL
/// handler there gets one that silently never fires, which is the failure the
/// enums exist to prevent.
///
/// Refusals are not in here. `Emitted` lists what actually compiled, so a
/// declaration the backend turned down keeps its variant — which is the only
/// place left to answer it.
priv struct Answered {
  inputs : Array[String]
  methods : Array[String]
  whens : Array[String]
  enriches : Array[String]
  enrich_scopes : Array[String]
}

///|
/// What a file with no script block answers: nothing, in every bucket.
fn Answered::none() -> Answered {
  { inputs: [], methods: [], whens: [], enriches: [], enrich_scopes: [] }
}

///|
/// What the compiled block answers. `None` — no block, or a component with no
/// schema to compile one against — answers nothing.
fn Answered::of(e : @emit_mbt.Emitted?) -> Answered {
  guard e is Some(e) else { return Answered::none() }
  {
    inputs: e.answers_input,
    methods: e.answers_methods,
    whens: e.answers_whens,
    enriches: e.answers_enriches,
    enrich_scopes: e.answers_enrich_scopes,
  }
}

///|
/// The doc lines an author-facing enum carries when the block already answered
/// some of its names: which ones are absent, and why an arm for one could
/// never run.
///
/// Every enum the author writes a match over gets this, because it is one
/// rule — what the block answers is routed before the author is consulted.
/// Only the MECHANISM differs between them, and the caller passes that; the
/// lines come back already `///`-prefixed, to be spliced under a headline.
fn absent_note(answered : Array[String], mechanism : String) -> String {
  if answered.is_empty() {
    return ""
  }
  let out = StringBuilder::new()
  out.write_string(
    "///\n/// Absent, because the script block answers them: \{answered.join(", ")}.\n",
  )
  for line in mechanism.split("\n") {
    out.write_string("/// \{line}\n")
  }
  out.to_string()
}

///|
/// The mechanism half of `absent_note` for a handler bucket. One wording for
/// all four, because it is one composition: `emit_comp.mbt` merges the block's
/// generated map over the bucket the author's match builds.
let bucket_mechanism : String = "The block's own handlers are merged into this bucket, so an arm for one of\nthese could never run."

///|
/// The subset of `names` the block did not answer — the ones an author still
/// has to write. Order is preserved, so the enum's variants stay sorted.
fn unanswered(names : Array[String], answered : Array[String]) -> Array[String] {
  names.filter(n => !answered.contains(n))
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
  /// Already-`///`-prefixed lines spliced under the headline — `absent_note`
  /// is the only thing that writes any.
  note? : String = "",
) -> Unit {
  out.write_string("///|\n/// \{doc}\n\{note}pub(all) enum \{type_name} {\n")
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
/// ones its script block declares. Sorted and de-duplicated, so a method that
/// is both called and declared is one enum case.
///
/// The second source is not redundant. Most methods a view declares by calling
/// (`$label`), but a method a PARENT calls — `containsText` on a list item,
/// which the list's `@when` asks every child regardless of the child's own
/// shape — appears in no view of the component that answers it. A state block
/// used to declare those as `func`, which put behaviour in a block whose own
/// header says it holds none; now they are `pred` and `compute` declarations,
/// beside every other callable.
fn declared_methods(surface : Surface) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for m in surface.methods {
    if !seen.contains(m) {
      seen[m] = ()
      out.push(m)
    }
  }
  out.sort_by((a, b) => a.lexical_compare(b))
  out
}

///|
/// The component's surface with what its script block declares folded in.
///
/// A `pred` or a `compute` in the block is a method this component answers,
/// exactly as a `$name` at a call site is — and the enum a `compute` match is
/// written over needs the name, which is the half no call site could supply.
///
/// The names are also what tells the BACKEND which bodies to compile, and in
/// which role: `emit_inline.mbt` hands this surface's methods, whens and
/// enrichers to `emit_mbt` as its `Roles`. That is why folding them in here
/// matters twice — once for the enum, once for the emission.
fn with_script(
  surface : Surface,
  file : @viewfile.ViewFile,
  comp : String,
) -> Surface raise GenError {
  guard file.script_for(comp) is Some(block) else { return surface }
  let decls = @tscript.parse_script(block.text) catch {
    e =>
      raise BadScriptBlock(
        comp~,
        line=block.line + line_of(block.text, e.span().start) - 1,
        message=e.message(),
      )
  }
  let methods = surface.methods.copy()
  for d in decls {
    if d.kind is (DPred | DCompute | DInvariant) && !methods.contains(d.name) {
      methods.push(d.name)
    }
  }
  methods.sort_by((a, b) => a.lexical_compare(b))
  { ..surface, methods, }
}

///|
/// The 1-based line of a character offset inside the block.
fn line_of(text : String, offset : Int) -> Int {
  let mut line = 1
  let mut i = 0
  for c in text {
    if i >= offset {
      break
    }
    if c == '\n' {
      line = line + 1
    }
    i = i + 1
  }
  line
}

///|
/// The MoonBit variant for a source name, from the pairs `variants_for` built.
fn variant_of(pairs : Array[(String, String)], name : String) -> String {
  for p in pairs {
    if p.0 == name {
      return p.1
    }
  }
  name
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
///
/// `answered` drops the names the block handles, on the rule `Answered` states.
/// A bucket the block answers ENTIRELY loses its enum along with its wrapper
/// parameter, by the same emptiness test a bucket the views never name does —
/// there is nothing left for an author to write.
fn emit_alter_bucket(
  out : StringBuilder,
  t : String,
  names : Array[String],
  answered : Array[String],
  suffix : String,
  doc : String,
  derives : String,
) -> Unit raise GenError {
  let names = unanswered(names, answered)
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
    note=absent_note(answered, bucket_mechanism),
  )
}

///|
/// One component's section of the generated types module.
fn emit_component(
  name : String,
  source_file : String,
  views : @viewfile.ViewSet,
  surface : Surface,
  state : @statedef.StateDef?,
  inits : Array[@statedef.InitState],
  debug_derive : Bool,
  /// What the file's script block answers, per bucket. Every enum an author
  /// writes a match over is trimmed against it, on the rule `Answered` states:
  /// `Msg`, `Method`, `When`, `Enrich` and `EnrichScope`.
  ///
  /// The `Input` enum is the one exception, and keeps them all. It keys `swap`,
  /// which wins over `update` and replaces the NODE rather than the state —
  /// something the block cannot say, so answering a name in the block must not
  /// take swapping it away.
  answered : Answered,
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
    emit_state(t, v, def, inits, derives, surface, out)
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
    let unanswered = surface.inputs.filter(i => {
      !answered.inputs.contains(i.name)
    })
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
    let answered_note = absent_note(
      answered.inputs,
      "`update` is consulted only for a dispatch the block did not claim, so\nan arm for one of these could never run.",
    )
    out.write_string(
      "///|\n" +
      "/// The Input arm of @component.Dispatch, decoded. Payload types are\n" +
      "/// inferred from the argument shapes written at the call sites, so a\n" +
      "/// handler added to \{source_file} breaks every `match` over this type\n" +
      "/// until it is handled.\n" +
      answered_note +
      "pub(all) enum \{t}Msg {\n",
    )
    for sig in unanswered {
      emit_msg_variant(out, sig, variant_of(input_variants, sig.name))
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
    for sig in unanswered {
      out.write_string("  ")
      emit_msg_arm(out, sig, variant_of(input_variants, sig.name))
    }
    out.write_string("      _ => Unknown(name, args)\n    },\n  )\n}\n\n")
  }

  // -- $-callables ---------------------------------------------------------
  // The views' `$name` calls PLUS the `pred` / `compute` declarations in the
  // script block. A method a parent calls on this component appears in neither
  // its views nor its update, so the block is the only place it can be named —
  // and without a case for it, the match the author writes could not answer it.
  // `unanswered` then drops the names the block itself handles.
  let all_methods = unanswered(declared_methods(surface), answered.methods)
  if !all_methods.is_empty() {
    let method_variants = variants_for(all_methods)
    emit_name_enum(
      out,
      "Every `$name` the views call.",
      "\{t}Method",
      "name",
      method_variants,
      derives,
      note=absent_note(answered.methods, bucket_mechanism),
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
    answered.whens,
    "When",
    "Every `@when` handler the views name.",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    surface.enriches,
    answered.enriches,
    "Enrich",
    "Every `@enrich-with` handler named INSIDE an `@each`.",
    derives,
  )
  emit_alter_bucket(
    out,
    t,
    surface.enrich_scopes,
    answered.enrich_scopes,
    "EnrichScope",
    "Every `@enrich-with` handler named with no `@each` around it.",
    derives,
  )
  // `@loop-with` has no declaration in the block language, so there is nothing
  // for it to answer and nothing to trim.
  emit_alter_bucket(
    out,
    t,
    surface.loop_withs,
    [],
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
  file : @viewfile.ViewFile,
  debug_derive? : Bool = true,
  hints? : Array[String] = [],
  program? : ProgramIndex,
) -> String raise GenError {
  emit_module_compiled(
    name,
    source_file,
    file,
    compile_file(file),
    debug_derive,
    hints,
    program,
  )
}

///|
pub fn emit_modules(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
  include_ir? : Bool = true,
  debug_derive? : Bool = true,
  hints? : Array[String] = [],
  program? : ProgramIndex,
) -> GeneratedModules raise GenError {
  let compiled = compile_file(file)
  let types_source = emit_module_compiled(
    name, source_file, file, compiled, debug_derive, hints, program,
  )
  let ir_source = if include_ir {
    Some(emit_ir_module_compiled(name, source_file, file, compiled)) catch {
      _ => None
    }
  } else {
    None
  }
  { types_source, ir_source }
}

///|
fn emit_module_compiled(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
  compiled : CompiledFile,
  debug_derive : Bool,
  hints : Array[String],
  program : ProgramIndex?,
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
    if !declared.contains(def.component_name(name)) {
      emit_state_only(def, file, name, debug_derive, out)
    }
  }
  // The caller's index when there is one — that is what makes a reference to a
  // component declared in ANOTHER file checkable. Without one the file is its
  // own whole program, which is what a single-file invocation means.
  let prog = match program {
    Some(p) => p
    None => ProgramIndex::of(file, name)
  }
  for compiled_comp in compiled.components {
    let comp = compiled_comp.raw
    let cname = comp.component_name(name)
    let state = state_for(file, cname, name)
    // A fixture is keyed by the schema's RAW component name, which is "" for
    // a bare `state { … }` — so the key comes from the same `def` the
    // fixtures were checked against, not from the resolved name.
    let init_key = match state {
      Some(d) => d.component
      None => cname
    }
    let inits = file.init.filter(p => p.0 == init_key).map(p => p.1)
    // Checked before emitting: a view that reads a field the schema does not
    // declare would otherwise emit a module that compiles and renders null.
    let surface = with_script(compiled_comp.surface, file, cname)
    let mut answered = Answered::none()
    if state is Some(def) {
      check_views(compiled_comp.views, def, prog, hints)
      // The same compile the IR module runs, for the same block — this path
      // wants two things out of it: the refusals, which are a diagnostic, and
      // what it answers, which is what the enums below are trimmed against.
      if inline_emit(
          file,
          cname,
          def,
          surface,
          value_prefix(cname),
          "\{type_prefix(cname)}State",
        )
        is Some(e) {
        // A declaration the MoonBit backend will not compile is not an error —
        // the design reserves the hardest sixth of the corpus for hand-written
        // MoonBit — but it IS something the author has to read, or they will
        // wonder why the handler they wrote in the block does nothing.
        for r in e.refusals {
          hints.push(
            "\{cname}: `\{r.name}` stays in MoonBit — \{r.why} (script-refusal)",
          )
        }
        answered = Answered::of(Some(e))
      }
    }
    emit_component(
      cname, source_file, comp, surface, state, inits, debug_derive, answered, out,
    )
  }
  out.to_string()
}

///|
/// The component names this file gives views to.
pub fn declared_components(
  file : @viewfile.ViewFile,
  name : String,
) -> Array[String] {
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
  file : @viewfile.ViewFile,
  name : String,
  debug_derive : Bool,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(def.component_name(name))
  let v = value_prefix(def.component_name(name))
  let derives = if debug_derive { "Eq, @debug.Debug" } else { "Eq" }
  let inits = file.init
    .filter(p => p.0 == def.component_name(name))
    .map(p => p.1)
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
  // A schema-only file has no call sites, so the `receive` merge has nothing
  // to merge and nothing to disagree with.
  emit_state(t, v, def, inits, derives, empty_surface, out)
  let no_views : @viewfile.ViewSet = {
    name: def.component_name(name),
    views: [],
    common_style: "",
    global_style: "",
  }
  emit_schema(t, "", def, empty_surface, no_views, inits, out)
}

///|
/// The schema entry for a component, or None when the file declares none.
fn state_for(
  file : @viewfile.ViewFile,
  comp : String,
  fallback : String,
) -> @statedef.StateDef? {
  for def in file.state {
    if def.component_name(fallback) == comp {
      return Some(def)
    }
  }
  None
}

///|
/// `@viewfile.split_file` in the generator's error vocabulary.
///
/// The splitter is a package down and raises its own `FileError`, which is
/// right for a card runtime that never generates anything. A caller who is
/// about to call `emit_module` wants one error type for the whole pipeline,
/// and `File` is only constructible here — so the conversion lives here,
/// once, instead of at every call site.
pub fn split_file(
  source : String,
  name? : String = "",
) -> @viewfile.ViewFile raise GenError {
  @viewfile.split_file(source, name~) catch {
    e => raise File(e)
  }
}

///|
pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError {
  emit_module(name, source_file, split_file(source, name~))
}
