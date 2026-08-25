// Emitting the per-component `component()` wrapper.
//
// The wrapper is how the generator wires its own output, and the next
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
  let answered = Answered::of(values)
  // The routers first. A wrapper is one `component()` call, and the functions
  // it names have to exist before it — so they are written here rather than
  // interleaved into the middle of the call being built below.
  let routers : Map[String, String] = Map([])
  for b in wrapper_buckets(t, s, surface, methods, answered) {
    if bucket_router(v, b, answered, out) is Some(fn_name) {
      routers[b.param] = fn_name
    }
  }
  // One branch, because `has_direct_codec` answers true for the whole StateTy
  // lattice.
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
  for b in wrapper_buckets(t, s, surface, methods, answered) {
    // No default: an absent bucket is `None`, and the call below turns that
    // into the empty map. Giving it `_ => None` instead would read as "answer
    // nothing", which is a different statement from "there is nothing here".
    //
    // A bucket the block answers whole gets no parameter at all — there is no
    // enum left to key it by, and nothing an author could add.
    if b.asks_author() {
      out.write_string("  \{b.param}? : (\{b.enum_}) -> (\{b.handler})?,\n")
    }
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
  out.write_string(wrapper_opt("lookup", "Array[@component.LookupSpec]", "[]"))
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
  for b in wrapper_buckets(t, s, surface, methods, answered) {
    // The two halves are disjoint by construction — the author's enum holds
    // exactly the names the router does not — so this is a merge and not a
    // precedence. The block's map goes in last anyway, on the rule `update~`
    // follows: what the file states is what runs, and the MoonBit beside it
    // answers what the file could not.
    let author = "match \{b.param} {\n" +
      "        Some(f) =>\n" +
      "          @component.build_bucket((\{b.all} : Array[\{b.enum_}]), \{b.enum_}::name, f)\n" +
      "        None => Map([])\n" +
      "      }"
    match (routers.get(b.param), b.asks_author()) {
      (Some(router), true) =>
        out.write_string(
          "    \{b.param}={\n" +
          "      let bucket = \{author}\n" +
          "      for k, h in \{router}() {\n" +
          "        bucket[k] = h\n" +
          "      }\n" +
          "      bucket\n" +
          "    },\n",
        )
      // Answered whole: the map the block built IS the bucket.
      (Some(router), false) => out.write_string("    \{b.param}=\{router}(),\n")
      (None, _) =>
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
/// What the block answers in one bucket, and the role its bodies were compiled
/// in — None for a bucket the block language cannot declare into.
///
/// `swap` has no declaration in the block language (a `swap` replaces the node,
/// which the block cannot say) and neither does `loop_with`, so there is
/// nothing to route to either.
fn bucket_role(
  param : String,
  answered : Answered,
) -> (@emit_mbt.Role, Array[String])? {
  match param {
    "compute" => Some((RMethod, answered.methods))
    "when" => Some((RWhen, answered.whens))
    "enrich" => Some((REnrich, answered.enriches))
    "enrich_scope" => Some((REnrichScope, answered.enrich_scopes))
    _ => None
  }
}

///|
/// The names the block answers in this bucket — empty for a bucket it cannot
/// declare into, and for a file with no block at all.
fn bucket_answers(param : String, answered : Answered) -> Array[String] {
  match bucket_role(param, answered) {
    Some((_, names)) => names
    None => []
  }
}

///|
/// The generated router for one bucket, and the name it is emitted under —
/// None when the block compiled nothing this bucket routes to.
///
/// It is the bucket's own `Map[String, H]`, already built. It is keyed by the
/// SOURCE name rather than by the bucket enum because the enum carries none
/// of these names: they are exactly the ones trimmed out of it, so the
/// author is never asked about them. Both halves land in the same map at the
/// wrapper, which is where the two are merged.
fn bucket_router(
  v : String,
  b : WrapperBucket,
  answered : Answered,
  into : StringBuilder,
) -> String? {
  guard bucket_role(b.param, answered) is Some((role, names)) else {
    return None
  }
  if names.is_empty() {
    return None
  }
  let name = "\{v}_inline_\{b.param}"
  let out = StringBuilder::new()
  out.write_string("///|\n")
  out.write_string(
    "/// The `\{b.param}` names the `<script type=\"tutuca/script\">` block answers.\n",
  )
  out.write_string("/// GENERATED — edit the block, not this.\n")
  out.write_string("fn \{name}() -> Map[String, \{b.handler}] {\n  {\n")
  for n in names {
    out.write_string(
      "    \{quote(n)}: \{@emit_mbt.value_fn_name(v, role, n)},\n",
    )
  }
  out.write_string("  }\n}\n\n")
  into.write_string(out.to_string())
  Some(name)
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
  /// to `@component.build_bucket`.
  ///
  /// TRIMMED of what the block answers, exactly as `enum_` is — the two have to
  /// agree, since one is the case list of the other. `[]` means the block
  /// answered the whole bucket, so there is no enum and nothing to ask for.
  all : String
}

///|
/// Whether the author gets a parameter for this bucket: only when something is
/// left for them to answer.
fn WrapperBucket::asks_author(self : WrapperBucket) -> Bool {
  self.all != "[]"
}

///|
/// The handler buckets, in `component()`'s own order — TRIMMED to the ones the
/// views actually name.
///
/// A bucket the views never use is not a parameter at all, so it
/// cannot be answered by mistake; and the ones that remain are keyed by a
/// generated enum rather than by a string, so the author writes a match the
/// compiler checks — which is what makes a `$name` or an `@when` added to a
/// view a build error instead of a handler silently never called.
///
/// The buckets are listed on the FULL name sets — a bucket the block answers
/// entirely is still passed to `component()`, it just has no parameter — while
/// `all` is trimmed to what is left for the author. `asks_author` is the split.
fn wrapper_buckets(
  t : String,
  s : String,
  surface : Surface,
  methods : Array[String],
  answered : Answered,
) -> Array[WrapperBucket] raise GenError {
  let out : Array[WrapperBucket] = []
  fn cases(param : String, names : Array[String]) -> String raise GenError {
    variant_list(unanswered(names, bucket_answers(param, answered)))
  }

  // `compute` answers `$name` in a VALUE position, so it is keyed by Method.
  if !methods.is_empty() {
    out.push({
      param: "compute",
      enum_: "\{t}Method",
      handler: "(\{s}, Array[@tutuca.Value], &@tutuca.Stack) -> @tutuca.Value",
      all: cases("compute", methods),
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
      handler: "(\{s}, @tutuca.Value, @tutuca.Value, @tutuca.Value, &@tutuca.Stack) -> Bool",
      all: cases("when", surface.whens),
    })
  }
  if !surface.enriches.is_empty() {
    out.push({
      param: "enrich",
      enum_: "\{t}Enrich",
      handler: "(\{s}, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value, &@tutuca.Stack) -> Unit",
      all: cases("enrich", surface.enriches),
    })
  }
  if !surface.enrich_scopes.is_empty() {
    out.push({
      param: "enrich_scope",
      enum_: "\{t}EnrichScope",
      handler: "(\{s}, &@tutuca.Stack) -> Map[String, @tutuca.Value]",
      all: cases("enrich_scope", surface.enrich_scopes),
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
