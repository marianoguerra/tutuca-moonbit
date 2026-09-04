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
  def : @statedef.StateDef,
  surface : Surface,
  /// The `<comp>_inline_update` this wrapper composes ahead of `update~`, when
  /// the file's script block compiled one.
  inline : String?,
  /// The block's compiled VALUE bodies, which the buckets below compose the
  /// same way — generated first, the author's consulted for what is left.
  values : @emit_mbt.Emitted?,
  /// The file-level const holding the spec block's source, when the file has
  /// one — `emit_spec_source`'s answer, threaded down rather than recomputed
  /// so every wrapper in a file names the same const.
  spec_source : String?,
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
  // One branch, because `has_direct_codec` answers true for the whole @tutuca.Ty
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
  out.write_string(wrapper_opt("initial", s, "\{s}::zero()"))
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
  // The block first, the author's `update` second. `Unhandled` is the only
  // answer that hands the name on: `Unchanged` means the block claimed it and
  // chose not to move, which stops here.
  //
  // There is no third link. A generated mutator is NOT reachable as a bare
  // message — `TypedInstance`'s handler refuses an unclaimed name with
  // `NoHandler` rather than falling through to the table, so that a typo in a
  // view cannot silently become a field write. The mutators are reached by
  // WRITING: `.items.removeAt @key`, `.count = 1`, or `$removeInItemsAt` as a
  // value. `@on.click="removeInItemsAt @key"` compiles and does nothing.
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
    "    initial~,\n" +
    "    common_style~,\n" +
    "    global_style~,\n" +
    update_arg,
  )
  let getters = def.properties.filter(p => {
    p.getter is Some(_) || answered.property_get.contains(p.name)
  })
  if !getters.is_empty() {
    out.write_string("    get_property={\n")
    for p in getters {
      match p.getter {
        Some(source) => {
          let field = source[1:].to_owned()
          out.write_string(
            "      " +
            quote(p.name) +
            ": s => @component.Fields::encode(s).get(" +
            quote(field) +
            ").unwrap_or(Null),\n",
          )
        }
        None =>
          out.write_string(
            "      " +
            quote(p.name) +
            ": s => " +
            @emit_mbt.value_fn_name(v, RMethod, p.name) +
            "(s, [], @tutuca.NullStack::{ }),\n",
          )
      }
    }
    out.write_string("    },\n")
  }
  let setters = def.properties.filter(p => {
    p.setter is Some(_) || answered.property_set.contains(p.name)
  })
  if !setters.is_empty() {
    out.write_string("    set_property={\n")
    for p in setters {
      match p.setter {
        Some(source) => {
          let field = source[1:].to_owned()
          out.write_string(
            "      " +
            quote(p.name) +
            ": (s, value) => {\n" +
            "        let fields = @component.Fields::encode(s)\n" +
            "        fields[" +
            quote(field) +
            "] = value\n" +
            "        match @component.Fields::decode(fields) {\n" +
            "          Some(next) => Next(next)\n" +
            "          None => Unchanged\n" +
            "        }\n" +
            "      },\n",
          )
        }
        None =>
          out.write_string(
            "      " +
            quote(p.name) +
            ": (s, value) => " +
            @emit_mbt.property_set_fn_name(v, p.name) +
            "(s, value),\n",
          )
      }
    }
    out.write_string("    },\n")
  }
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
  // Not a parameter of the wrapper. Everything else here is something the
  // author might legitimately pass differently; the block a component was
  // DECLARED in is not, and a wrapper that let it be overridden would let the
  // generators be derived from a schema the component does not have.
  match spec_source {
    Some(name) => out.write_string("    spec=\{name},\n")
    None => ()
  }
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
    "bind_with" => Some((RBindWith, answered.bind_withs))
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
  let out = StringBuilder()
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

  // `compute` answers `$name` in a VALUE position, and the enum is named for
  // the bucket it keys.
  if !methods.is_empty() {
    out.push({
      param: "compute",
      enum_: "\{t}Compute",
      handler: "(\{s}, Array[@tutuca.Value], &@tutuca.Stack) -> @tutuca.Value",
      all: cases("compute", methods),
    })
  }
  // There is no `swap` bucket. A handler that supersedes this node with
  // another component's instance answers `Replace(v)` from the one `update`
  // match, which is where every other answer already comes from.
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
  if !surface.bind_withs.is_empty() {
    out.push({
      param: "bind_with",
      enum_: "\{t}EnrichScope",
      handler: "(\{s}, &@tutuca.Stack) -> Map[String, @tutuca.Value]",
      all: cases("bind_with", surface.bind_withs),
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

///|
/// The `<script type="tutuca/spec">` block, as source, for the `spec~` a
/// wrapper passes to `component()`.
///
/// Doc comments go. What is kept has to be re-PARSEABLE — that is the whole
/// contract, since a reader is `@statedef.parse_state` and nothing else — and
/// prose is the half of a block that no parser reads and every binary would
/// otherwise carry. `svg_more.html`'s block is 1.4 KB of which most is the
/// explanation of why the two limits are named, which is worth having in the
/// file the author edits and worth nothing in a wasm module.
///
/// Returns the const's NAME, or None when the file declares no block. One
/// const per FILE rather than per component: a `struct` or `enum` in the block
/// is file-level, and `parse_state` folds those into every `StateDef` it
/// returns — so a per-component slice would be a slice that no longer parses.
fn emit_spec_source(
  v : String,
  file : @viewfile.ViewFile,
  out : StringBuilder,
) -> String? {
  guard file.state_block is Some(block) else { return None }
  let text = strip_doc_comments(block.text)
  guard text != "" else { return None }
  let name = "\{v}_spec_source"
  emit_string_let(
    out,
    "This file's `<script type=\"tutuca/spec\">` block, as source, with its\n" +
    "/// doc comments removed.\n" +
    "///\n" +
    "/// The schema each component carries is this block's PROJECTION, and the\n" +
    "/// projection is lossy exactly where a generator needs it: a rule reaches\n" +
    "/// `SchemaInfo` as a name with no body, and a message as a name with no\n" +
    "/// payload. Re-parsing this recovers both — see `testing/fuzz`.",
    name,
    text,
  )
  Some(name)
}

///|
/// Drop `///` doc-comment lines, and any blank line left leading a block.
///
/// Line-oriented on purpose: a `///` inside a `format` string is a `///` in
/// the middle of a line, and this only ever looks at what a line STARTS with.
fn strip_doc_comments(text : String) -> String {
  let kept : Array[String] = []
  for line in text.split("\n") {
    let l = line.to_owned()
    if l.trim(chars=" \t").has_prefix("///") {
      continue
    }
    // A blank line that only separated prose from what follows leaves a gap
    // the block does not need; one between two declarations is kept.
    if l.trim(chars=" \t\r") == "" &&
      (kept.is_empty() || kept[kept.length() - 1] == "") {
      continue
    }
    kept.push(l)
  }
  while kept.length() > 0 && kept[kept.length() - 1].trim(chars=" \t\r") == "" {
    kept.pop() |> ignore
  }
  kept.join("\n")
}
