// wasm-gc host for the storybook gallery. The SAME compiled example registry
// the headless tests drive is grouped into sections (storybook/) and mounted as
// one live gallery app (storybook/ui). JS calls `mount()` after load, then
// `on_event` on each DOM event (closures can't cross into JS on wasm-gc).

///|
fn main {

}

///|
/// Per-pane Lint text: the CLI's component checker, formatted one finding per
/// line (or a clean-bill message). Pure, so it runs on wasm-gc too.
fn lint_text(comp : @component.Component) -> String {
  let findings = @cli.check_component(comp)
  if findings.is_empty() {
    "No issues found."
  } else {
    let lines : Array[String] = []
    for f in findings {
      lines.push(f.line())
    }
    lines.join("\n")
  }
}

///|
/// Mount the whole gallery on #app. Called from JS once the DOM is ready.
pub fn mount() -> Unit {
  let g = @core.global_this()
  let doc = g._get("document")
  let root_el = doc._call("getElementById", [@core.any("app")])
  if @core.is_nullish(root_el) {
    println("no #app element")
    return
  }
  let sections = @sb.sections_of(@sb.stories())
  let root = @wdom.WasmNode::of_any(root_el)
  let opts = @vdom.RenderOpts::new(@wdom.WasmNode::of_any(doc))
  let app = try! @sbui.mount(sections, root, opts, lint=lint_text)
  @wglue.install(app)
  @wglue.install_styles(app, @wdom.WasmNode::of_any(doc))
  // publish the collected margaui class set (gallery chrome + every example's
  // classes) for index.html's margaui compile step — same path as the other
  // wasm demos.
  publish_classes(app.scope.comps.collect_classes())
}

///|
/// Publish the collected margaui class set as a JS array on globalThis so the
/// page's margaui compile step can turn it into CSS.
fn publish_classes(classes : Array[String]) -> Unit {
  let arr = @core.new_array()
  for c in classes {
    let _ = arr._call("push", [@core.any(c)])
  }
  @core.global_this()._set("__tutuca_classes", arr)
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}
