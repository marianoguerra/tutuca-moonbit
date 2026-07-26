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
  out : StringBuilder,
) -> Unit {
  let s = "\{t}State"
  let filled = if has_direct_codec(def) {
    "/// states filled in — its name, its compiled views, its styles, its schema\n" +
    "/// and its direct codec. What is left is the code no generator can write.\n"
  } else {
    "/// states filled in — its name, its compiled views, its styles and its\n" +
    "/// schema. What is left is the code no generator can write.\n"
  }
  out.write_string(
    "///|\n" +
    "/// The \{name} component: `component()` with everything the view file already\n" +
    filled +
    "///\n" +
    "/// `init` defaults to the zero state and `name` to the name the template\n" +
    "/// id declares — pass either when yours differs. The signature below is\n" +
    "/// the whole story: anything not a parameter here, the view file states.\n" +
    "fn \{v}_component(\n",
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
  for b in wrapper_buckets(s) {
    out.write_string(wrapper_opt(b.0, b.1, "Map([])"))
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
  for b in wrapper_buckets(s) {
    out.write_string("    \{b.0}~,\n")
  }
  out.write_string("    specs~,\n    provide~,\n    lookup~,\n")
  // The codec is skipped for a state the generator cannot convert field by
  // field; naming it here would be naming a function that was never emitted.
  // Without it `component()` uses the JSON bridge, which is what such a state
  // needs anyway.
  if has_direct_codec(def) {
    out.write_string("    encode=\{v}_encode,\n    decode=\{v}_decode,\n")
  }
  out.write_string("    schema=\{v}_schema(),\n  )\n}\n\n")
}

///|
/// The handler buckets, in `component()`'s own order: (parameter, type).
///
/// Emitted whole rather than trimmed to what the views use — `Surface`
/// carries no @when/@enrich-with/@loop-with names, so trimming could only
/// ever be partial, and a signature that wobbles as the views change buys
/// nothing.
fn wrapper_buckets(s : String) -> Array[(String, String)] {
  [
    ("compute", "Map[String, (\{s}, Array[@tutuca.Value]) -> @tutuca.Value]"),
    (
      "swap",
      "Map[String, (\{s}, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?]",
    ),
    (
      "when",
      "Map[String, (\{s}, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool]",
    ),
    (
      "enrich",
      "Map[String, (\{s}, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit]",
    ),
    ("enrich_scope", "Map[String, (\{s}) -> Map[String, @tutuca.Value]]"),
    (
      "loop_with",
      "Map[String, (\{s}, @tutuca.Value, @component.LoopCtx) -> @component.LoopWith]",
    ),
  ]
}
