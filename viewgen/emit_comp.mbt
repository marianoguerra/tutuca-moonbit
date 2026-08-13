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
  _def : @statedef.StateDef,
  surface : Surface,
  /// The `<comp>_inline_update` this wrapper composes ahead of `update~`, when
  /// the file's script block compiled one.
  inline : String?,
  /// The block's compiled VALUE bodies, which the buckets below compose the
  /// same way — generated first, the author's consulted for what is left.
  values : @emit_mbt.Emitted?,
  out : StringBuilder,
) -> Unit raise GenError {
  let methods = declared_methods(surface)
  let s = "\{t}State"
  // The routers first. A wrapper is one `component()` call, and the functions
  // it names have to exist before it — so they are written here rather than
  // interleaved into the middle of the call being built below.
  let routers : Map[String, String] = Map([])
  for b in wrapper_buckets(t, s, surface, methods) {
    if bucket_router(v, b, values, out) is Some(fn_name) {
      routers[b.param] = fn_name
    }
  }
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
    "  update? : (\{s}, @component.Dispatch, &@tutuca.Ctx) -> @component.Update[\{s}],\n",
  )
  for b in wrapper_buckets(t, s, surface, methods) {
    // No default: an absent bucket is `None`, and the call below turns that
    // into the empty map. Giving it `_ => None` instead would read as "answer
    // nothing", which is a different statement from "there is nothing here".
    out.write_string("  \{b.param}? : (\{b.enum_}) -> (\{b.handler})?,\n")
  }
  // What is left of `specs~`, split into the two things it actually did. The
  // component a slot holds is part of the field's TYPE now — a sibling
  // interface, or a `resource` for one from another module — and the kind it
  // could also restate is declared. These two are what a type cannot say:
  // `slots~` for a component whose name kebab-case cannot round-trip, and
  // `slot_args~` for the arguments a child is built with, which are a value.
  out.write_string(wrapper_opt("slots", "Map[String, String]", "Map([])"))
  out.write_string(
    wrapper_opt(
      "slot_args", "Map[String, Map[String, @tutuca.Value]]", "Map([])",
    ),
  )
  out.write_string(wrapper_opt("provide", "Map[String, String]", "Map([])"))
  out.write_string(
    wrapper_opt("lookup", "Map[String, @component.LookupSpec]", "Map([])"),
  )
  // The block first, the author's `update` second, the generated mutators
  // last. `Unhandled` is the only answer that hands the name on: `Unchanged`
  // means the block claimed it and chose not to move, which stops here.
  let update_arg = match inline {
    Some(f) =>
      "    update=(s, msg, ctx) => match \{f}(s, msg, ctx) {\n" +
      "      Unhandled =>\n" +
      "        match update {\n" +
      "          Some(u) => u(s, msg, ctx)\n" +
      "          None => Unhandled\n" +
      "        }\n" +
      "      answered => answered\n" +
      "    },\n"
    None => "    update?=update,\n"
  }
  out.write_string(
    ") -> @component.Component {\n" +
    "  @component.component(\n" +
    "    name~,\n" +
    "    views~,\n" +
    "    init~,\n" +
    "    common_style~,\n" +
    "    global_style~,\n" +
    update_arg,
  )
  for b in wrapper_buckets(t, s, surface, methods) {
    // The block first, the author second — the same precedence `update~` has,
    // for the same reason: what the file states is what runs, and the MoonBit
    // beside it answers what the file could not.
    match routers.get(b.param) {
      Some(router) =>
        out.write_string(
          "    \{b.param}=@component.build_bucket(\n" +
          "      (\{b.all} : Array[\{b.enum_}]),\n" +
          "      \{b.enum_}::name,\n" +
          "      k => match \{router}(k) {\n" +
          "        Some(f) => Some(f)\n" +
          "        None =>\n" +
          "          match \{b.param} {\n" +
          "            Some(g) => g(k)\n" +
          "            None => None\n" +
          "          }\n" +
          "      },\n" +
          "    ),\n",
        )
      None =>
        out.write_string(
          "    \{b.param}=match \{b.param} {\n" +
          "      Some(f) =>\n" +
          "        @component.build_bucket((\{b.all} : Array[\{b.enum_}]), \{b.enum_}::name, f)\n" +
          "      None => Map([])\n" +
          "    },\n",
        )
    }
  }
  out.write_string(
    "    slots~,\n    slot_args~,\n    provide~,\n    lookup~,\n",
  )
  out.write_string("  )\n}\n\n")
}

///|
/// The generated router for one bucket, and the name it is emitted under —
/// None when the block compiled nothing this bucket routes to.
///
/// It is a `match` over the bucket's own enum, which is why it is written here
/// rather than by the backend: the enum and its variant spellings are this
/// file's, and the functions it names are `emit_mbt`'s. `value_fn_name` is the
/// one thing both sides agree on.
fn bucket_router(
  v : String,
  b : WrapperBucket,
  values : @emit_mbt.Emitted?,
  into : StringBuilder,
) -> String? raise GenError {
  guard values is Some(e) else { return None }
  let (role, answered) = match b.param {
    "compute" => (@emit_mbt.Role::RMethod, e.answers_methods)
    "when" => (RWhen, e.answers_whens)
    "enrich" => (REnrich, e.answers_enriches)
    "enrich_scope" => (REnrichScope, e.answers_enrich_scopes)
    // `swap` and `loop_with` have no declaration in the block language, so
    // there is nothing here to route to them.
    _ => return None
  }
  if answered.is_empty() {
    return None
  }
  let name = "\{v}_inline_\{b.param}"
  let out = StringBuilder::new()
  out.write_string("///|\n")
  out.write_string(
    "/// The `\{b.param}` names the `<script type=\"tutuca/script\">` block answers.\n",
  )
  out.write_string("/// GENERATED — edit the block, not this.\n")
  out.write_string("fn \{name}(k : \{b.enum_}) -> (\{b.handler})? {\n")
  out.write_string("  match k {\n")
  let all = variants_for(answered)
  for pair in all {
    out.write_string(
      "    \{pair.1} => Some(\{@emit_mbt.value_fn_name(v, role, pair.0)})\n",
    )
  }
  // A wildcard only when one is reachable: the enum carries every name the
  // views use, and a `match` that already covers them all would be warned
  // about for the arm it cannot reach.
  if all.length() < variants_count(b.all) {
    out.write_string("    _ => None\n")
  }
  out.write_string("  }\n}\n\n")
  into.write_string(out.to_string())
  Some(name)
}

///|
/// How many variants a bucket's `all` list holds — it is the array literal
/// this file wrote, so counting its separators is exact.
fn variants_count(all : String) -> Int {
  if all == "[]" {
    return 0
  }
  let mut n = 1
  for c in all {
    if c == ',' {
      n = n + 1
    }
  }
  n
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
