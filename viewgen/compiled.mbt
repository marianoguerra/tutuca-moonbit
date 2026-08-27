// The shared view-compilation artifact. The types emitter, schema checker and
// IR emitter all consume these values so a CLI generation job parses each view
// once.

///|
priv struct CompiledView {
  raw : @viewfile.RawView
  root : @anode.ANode
  events : Array[@anode.NodeEvents]
}

///|
priv struct CompiledComponent {
  raw : @viewfile.ViewSet
  views : Array[CompiledView]
  surface : Surface
}

///|
priv struct CompiledFile {
  components : Array[CompiledComponent]
}

///|
fn compile_view(
  view : @viewfile.RawView,
  scope : FileMacros,
) -> CompiledView raise GenError {
  let collector = IssueCollector::{ issues: [], }
  let px = @anode.ParseContext::new(handler=collector)
  let v = @anode.View::new(view.name, raw_view=view.source)
  v.compile(px, scope) catch {
    RecursiveMacro(name) =>
      raise ViewParseIssue(view=view.name, issue="recursive macro '\{name}'")
  }
  if collector.issues is [issue, ..] {
    raise ViewParseIssue(view=view.name, issue~)
  }
  check_macros_resolved(view.name, px, scope)
  guard v.anode is Some(root) else { raise EmptyView(view.name) }
  let tree = strip_macro_calls(root)
  strip_data_vid(tree)
  { raw: view, root: tree, events: px.events, }
}

///|
fn compile_views(
  views : Array[@viewfile.RawView],
  scope : FileMacros,
) -> Array[CompiledView] raise GenError {
  let out : Array[CompiledView] = []
  for view in views {
    out.push(compile_view(view, scope))
  }
  out
}

///|
fn surface_of(views : Array[CompiledView]) -> Surface raise GenError {
  let collect = Collect::new()
  let inputs : Map[String, InputSig] = Map([])
  for view in views {
    walk_view(view.raw.name, view.root, view.events, collect, inputs)
  }
  finish_surface(collect, inputs)
}

///|
fn compile_component(
  views : @viewfile.ViewSet,
  scope : FileMacros,
  def : @statedef.StateDef?,
) -> CompiledComponent raise GenError {
  let compiled = compile_views(views.views, scope)
  lower_binds(compiled, def)
  { raw: views, views: compiled, surface: surface_of(compiled), }
}

///|
fn compile_file(
  file : @viewfile.ViewFile,
  name : String,
) -> CompiledFile raise GenError {
  let scope = FileMacros::of(file.macros)
  let components : Array[CompiledComponent] = []
  for comp in file.components {
    let cname = comp.component_name(name)
    components.push(
      compile_component(comp, scope, state_for(file, cname, name)),
    )
  }
  { components, }
}
