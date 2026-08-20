// The script block, compiled.
//
// `tscript/emit_mbt` does the work; this is the seam that hands it the three
// things it needs — the block, the schema, and the argument types the views
// imply — and decides where its output goes.
//
// It goes beside the WRAPPER rather than beside the state type, and for the
// wrapper's own reason: the two arrive and leave together. The wrapper is what
// composes the emitted function ahead of the author's `update~`, and a file
// with no IR module has neither. What the types module carries instead is the
// REFUSALS, as hints, because that path is the one `gen-views` reports
// diagnostics from and a refusal is a thing the author has to read.

///|
/// The generated function's name: `<comp>_inline_update`, in the value-prefix
/// spelling every other generated function uses.
fn inline_fn_name(v : String) -> String {
  "\{v}_inline_update"
}

///|
/// Compile this component's script block, or None when it has none.
///
/// Never raises. A block that does not parse is reported by `with_script`,
/// which every path already goes through before this one — so reaching here
/// with an unparseable block cannot happen, and answering None if it somehow
/// did is better than a second wording of one failure.
fn inline_emit(
  file : @viewfile.ViewFile,
  comp : String,
  def : @statedef.StateDef,
  surface : Surface,
  v : String,
  state_ty : String,
) -> @emit_mbt.Emitted? {
  guard file.script_for(comp) is Some(block) else { return None }
  let decls = @tscript.parse_script(block.text) catch { _ => return None }
  Some(
    @emit_mbt.emit(
      decls,
      def,
      state_ty~,
      fn_name=inline_fn_name(v),
      prefix=v,
      // Which name is reached HOW, from the views. The backend cannot know:
      // a `pred` read as `$name` and the same `pred` named by an `@when` are
      // two functions with different things in scope, and only a call site
      // says which of them exists.
      roles={
        methods: declared_methods(surface),
        whens: surface.whens,
        enriches: surface.enriches,
        enrich_scopes: surface.enrich_scopes,
      },
      surface=inline_surface(surface),
    ),
  )
}

///|
/// The checker's view of the surface: the argument types the views infer, per
/// input name.
///
/// `viewgen`'s `Surface` carries more than the backend needs (ids, whens, view
/// names) and spells its types as `ArgType`, which is the view language's own
/// three-way answer — known, disagreed-about, or absent. Only the first is a
/// type the emitter can decode a parameter at; the other two arrive as None,
/// which is exactly "bind it raw and refuse a typed use".
fn inline_surface(surface : Surface) -> @check.Surface {
  let inputs : Map[String, Array[@statedef.StateTy?]] = Map([])
  for sig in surface.inputs {
    inputs[sig.name] = match sig.args {
      Some(ts) => ts.map(arg_state_ty)
      None => []
    }
  }
  { inputs, knows_views: true, comps: [] }
}

///|
/// One inferred argument type, as the schema would spell it.
fn arg_state_ty(t : ArgType) -> @statedef.StateTy? {
  match t {
    VDouble => Some(TFloat)
    VString => Some(TText)
    VBool => Some(TBool)
    // `@value`, a bind, a `$method`, a disagreement between two call sites:
    // unknown, which is not wrong. The parameter binds raw.
    VValue => None
  }
}
