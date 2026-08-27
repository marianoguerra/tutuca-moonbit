// The set of components one generation job can see.
//
// Everything else in viewgen answers a question about ONE component: its
// fields, its handlers, its views. Two questions need more than that:
//
//   - `<x render=".slot" as="edit">` — does the component in that slot have an
//     `edit` view? A miss falls back to that component's `main` view at run
//     time, so the site renders the wrong view rather than reporting anything.
//   - `.field` inside a loop over `list<todo>` — the element type NAMES the Todo
//     component, and its schema is what the read has to be checked against.
//
// An index is built once per invocation and shared by every component checked
// under it, so pointing the generator at a directory checks references ACROSS
// files, not only within one.
//
// The one rule it must not break is the one at the head of check_state.mbt: a
// component absent from the index is unknown, and unknown is not wrong. That is
// what makes a partial invocation safe — `tutuca gen-views one.html` still
// works and simply checks less than `tutuca gen-views src/` does.

///|
/// Component name -> its schema, and component name -> the views a template
/// gives it. Two maps rather than one record because the two halves come from
/// different places: a file may declare a schema for a component it gives no
/// templates to (a component whose views are built in MoonBit), and it may give
/// templates to a component that declares no schema.
pub struct ProgramIndex {
  defs : Map[String, @statedef.StateDef]
  views : Map[String, Array[String]]
}

///|
pub fn ProgramIndex::new() -> ProgramIndex {
  { defs: Map([]), views: Map([]) }
}

///|
/// Fold one view file in. `fallback` is the component name for a file whose
/// templates do not name one — the same `--name` the emitter uses, so the index
/// and the generated module cannot disagree about what a component is called.
///
/// Later files win a name collision. Two files claiming one component name is
/// a project-level mistake this cannot diagnose (it has no path to name), and
/// picking a winner keeps the table total.
pub fn ProgramIndex::add(
  self : ProgramIndex,
  file : @viewfile.ViewFile,
  fallback : String,
) -> Unit {
  for def in file.state {
    self.defs[def.component_name(fallback)] = def
  }
  for comp in file.components {
    self.views[comp.component_name(fallback)] = comp.views.map(v => v.name)
  }
}

///|
/// The index for one file on its own — what `emit_module` builds when the
/// caller supplies none.
pub fn ProgramIndex::of(
  file : @viewfile.ViewFile,
  fallback : String,
) -> ProgramIndex {
  let idx = ProgramIndex::new()
  idx.add(file, fallback)
  idx
}

///|
/// Validate protocol declarations and implementation claims across the whole
/// generation batch. A one-file invocation naturally proves less and may be
/// gradual; a directory build can reach strict mode.
pub fn ProgramIndex::protocol_validation(
  self : ProgramIndex,
) -> @statedef.ProtocolValidation {
  let defs : Array[@statedef.StateDef] = []
  for _, def in self.defs {
    defs.push(def)
  }
  let validation = @statedef.validate_protocols(defs)
  for _, def in self.defs {
    let local_views = self.views.get(def.component).unwrap_or([])
    for binding in def.view_bindings {
      if !local_views.contains(binding.source) {
        validation.diagnostics.push({
          code: ProtocolViewMissing,
          component: def.component,
          protocol_id: binding.protocol_id,
          member_name: binding.member_name,
          message: "protocol view `\{binding.member_name}` maps to missing local view `\{binding.source}`",
          error: true,
          span: binding.span,
        })
      }
    }
  }
  if !validation.diagnostics.is_empty() {
    { ..validation, mode: Gradual }
  } else {
    validation
  }
}
