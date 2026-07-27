// Emitting the per-component `component()` wrapper.
//
// A hand-written component definition used to restate what the view file
// already says: its name, its compiled views, its styles, its codec and its
// schema. The cost was never the typing — it was that each new static fact
// the generator learned had to be threaded through every call site by hand,
// and so it never was: `<v>_schema()` landed in every generated module and
// was passed by three components.
//
// The wrapper inverts that: the generator wires its own output, and the next
// fact reaches every component by regenerating. What is left at the call site
// is the code no generator can write.
//
// It lives in the IR module rather than the types module because it names
// `<v>_views()`, and this way it exists exactly when the compiled views do —
// `--no-ir` and a view holding an unexpanded macro both take the two away
// together. Being monomorphic in `<T>State` it is also what lets the call
// site drop the `(s : CounterState, ...)` annotations that the generic
// `component()` needed as a seed.

///|
/// One optional parameter, as `name? : Type = default`.
fn wrapper_opt(name : String, ty : String, default : String) -> String {
  "  \{name}? : \{ty} = \{default},\n"
}

///|
/// Every case of a handler enum, as a MoonBit array literal.
///
/// The same `variants_for` the enum itself was emitted from, so the list and
/// the declaration cannot disagree — and it raises on the same collision, which
/// the enum has already refused by the time this runs.
fn variant_list(names : Array[String]) -> String raise GenError {
  "[" + variants_for(names).map(p => p.1).join(", ") + "]"
}

///|
/// The wrapper: `component()` with everything the view file states already
/// filled in.
///
/// Emitted only for a component that has BOTH templates and a schema — the
/// state type is what makes the parameters typed, and the views are what
/// there would be nothing to default without.
fn emit_wrapper(
  name : String,
  t : String,
  v : String,
  def : @statedef.StateDef,
  surface : Surface,
  out : StringBuilder,
) -> Unit raise GenError {
  let methods = declared_methods(surface, Some(def))
  let s = "\{t}State"
  // One branch, because `has_direct_codec` answers true for the whole StateTy
  // lattice — the shape it used to discriminate was a state the generator
  // could not convert field by field, which fell back to a JSON bridge that no
  // longer exists.
  let filled = "/// states filled in — its name, its compiled views and its styles. The\n" +
    "/// schema and the codec are not passed at all: `\{s}` states them\n" +
    "/// through `@component.Fields`, and `component()` reads them off the\n" +
    "/// bound. What is left is the code no generator can write.\n"
  out.write_string(
    "///|\n" +
    "/// The \{name} component: `component()` with everything the view file already\n" +
    filled +
    "///\n" +
    "/// `init` defaults to the zero state and `name` to the name the template\n" +
    "/// id declares — pass either when yours differs. The signature below is\n" +
    "/// the whole story: anything not a parameter here, the view file states.\n" +
    "pub fn \{v}_component(\n",
  )
  out.write_string(wrapper_opt("name", "String", quote(name)))
  out.write_string(
    wrapper_opt("views", "Map[String, @anode.View]", "\{v}_views()"),
  )
  out.write_string(wrapper_opt("init", s, "\{s}::zero()"))
  out.write_string(wrapper_opt("common_style", "String", "\{v}_common_style"))
  out.write_string(wrapper_opt("global_style", "String", "\{v}_global_style"))
  // No default: `component()` takes an update as an Option, and this one is
  // forwarded as one rather than being given an empty stand-in.
  out.write_string(
    "  update? : (\{s}, @component.Dispatch, &@tutuca.Ctx) -> \{s}?,\n",
  )
  for b in wrapper_buckets(t, s, surface, methods) {
    // No default: an absent bucket is `None`, and the call below turns that
    // into the empty map. Giving it `_ => None` instead would read as "answer
    // nothing", which is a different statement from "there is nothing here".
    out.write_string("  \{b.param}? : (\{b.enum_}) -> (\{b.handler})?,\n")
  }
  out.write_string(
    wrapper_opt("specs", "Map[String, @component.FieldSpec]", "Map([])"),
  )
  out.write_string(wrapper_opt("provide", "Map[String, String]", "Map([])"))
  out.write_string(
    wrapper_opt("lookup", "Map[String, @component.LookupSpec]", "Map([])"),
  )
  out.write_string(
    ") -> @component.Component {\n" +
    "  @component.component(\n" +
    "    name~,\n" +
    "    views~,\n" +
    "    init~,\n" +
    "    common_style~,\n" +
    "    global_style~,\n" +
    "    update?=update,\n",
  )
  for b in wrapper_buckets(t, s, surface, methods) {
    out.write_string(
      "    \{b.param}=match \{b.param} {\n" +
      "      Some(f) =>\n" +
      "        @component.build_bucket((\{b.all} : Array[\{b.enum_}]), \{b.enum_}::name, f)\n" +
      "      None => Map([])\n" +
      "    },\n",
    )
  }
  out.write_string("    specs~,\n    provide~,\n    lookup~,\n")
  out.write_string("  )\n}\n\n")
}

///|
/// One handler bucket on the wrapper: the parameter, the enum that keys it,
/// the handler it answers with, and the builder that turns the two into the
/// map `component()` still takes.
priv struct WrapperBucket {
  param : String
  enum_ : String
  handler : String
  /// Every case of `enum_`, as the MoonBit array literal the call site passes
  /// to `@component.build_bucket`. The bucket used to be built by a generated
  /// function per component that closed over this list; the list is the only
  /// part that varied, so it is passed instead.
  all : String
}

///|
/// The handler buckets, in `component()`'s own order — TRIMMED to the ones the
/// views actually name.
///
/// It used to emit all six as `Map[String, …]`, on the reasoning that
/// `Surface` carried no @when/@enrich-with/@loop-with names so trimming could
/// only ever be partial. It carries them now, and both halves of that change
/// matter. A bucket the views never use is not a parameter at all, so it
/// cannot be answered by mistake; and the ones that remain are keyed by a
/// generated enum rather than by a string, so the author writes a match the
/// compiler checks — which is what makes a `$name` or an `@when` added to a
/// view a build error instead of a handler silently never called.
fn wrapper_buckets(
  t : String,
  s : String,
  surface : Surface,
  methods : Array[String],
) -> Array[WrapperBucket] raise GenError {
  let out : Array[WrapperBucket] = []
  // `compute` answers `$name` in a VALUE position, so it is keyed by Method.
  if !methods.is_empty() {
    out.push({
      param: "compute",
      enum_: "\{t}Method",
      handler: "(\{s}, Array[@tutuca.Value]) -> @tutuca.Value",
      all: variant_list(methods),
    })
  }
  // `swap` does NOT share that enum, though it reads like it should. A swap
  // handler answers an Input dispatch — component/instance.mbt checks the swap
  // bucket before `update` for exactly the names `@on` raises — so its keys are
  // the input names, and it is `update`'s alternative rather than `compute`'s:
  // the one that may replace this node with a different component's instance.
  if !surface.inputs.is_empty() {
    out.push({
      param: "swap",
      enum_: "\{t}Input",
      handler: "(\{s}, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?",
      all: variant_list(surface.inputs.map(i => i.name)),
    })
  }
  if !surface.whens.is_empty() {
    out.push({
      param: "when",
      enum_: "\{t}When",
      handler: "(\{s}, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool",
      all: variant_list(surface.whens),
    })
  }
  if !surface.enriches.is_empty() {
    out.push({
      param: "enrich",
      enum_: "\{t}Enrich",
      handler: "(\{s}, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit",
      all: variant_list(surface.enriches),
    })
  }
  if !surface.enrich_scopes.is_empty() {
    out.push({
      param: "enrich_scope",
      enum_: "\{t}EnrichScope",
      handler: "(\{s}) -> Map[String, @tutuca.Value]",
      all: variant_list(surface.enrich_scopes),
    })
  }
  if !surface.loop_withs.is_empty() {
    out.push({
      param: "loop_with",
      enum_: "\{t}LoopWith",
      handler: "(\{s}, @tutuca.Value, @component.LoopCtx) -> @component.LoopWith",
      all: variant_list(surface.loop_withs),
    })
  }
  out
}
