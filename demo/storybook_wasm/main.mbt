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
/// The mounted gallery app, stashed so the `on_popstate` export can re-restore
/// URL state on Back/Forward. tutuca has no lifecycle, so — like the JS
/// storybook's `window.addEventListener("popstate", …)` — the host re-sends
/// `init`, which re-runs the shell's `loadState` restore.
let current_app : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
/// The browser-history request handlers wired into the gallery's root scope:
/// `loadState` reads the query string, `persistState` writes it. Kept in the
/// host (not storybook/ui) so the pure gallery package never depends on the JS
/// FFI — the same split as the JS storybook (mount.js owns the URL effects).
fn url_request_handlers() -> Map[String, @component.RequestFn] {
  {
    "loadState": @component.RequestFn((_args, respond) => {
      let params = parse_query(
        @core.global_this()._get("location")._get("search").to_string(),
      )
      let get = fn(k : String) -> @tutuca.Value {
        Str(params.get(k).unwrap_or(""))
      }
      respond(
        Ok(
          Map({
            "story": get("story"),
            "focus": get("focus"),
            "filter": get("filter"),
          }),
        ),
      )
    }),
    "persistState": @component.RequestFn((args, respond) => {
      match args {
        [Map(m), push] => write_url(m, push is Bool(true))
        _ => ()
      }
      respond(Ok(Null))
    }),
  }
}

///|
/// URL-decode a query-string fragment via the global decodeURIComponent
/// (constructor-free FFI, so it works on wasm-gc where `mizchi/js` — js-only —
/// is unavailable). "+" is a space in query strings; decode it first.
fn uri_decode(s : String) -> String {
  @core.global_this()
  ._call("decodeURIComponent", [@core.any(s.replace(old="+", new="%20"))])
  .to_string()
}

///|
/// URL-encode a value for the query string.
fn uri_encode(s : String) -> String {
  @core.global_this()._call("encodeURIComponent", [@core.any(s)]).to_string()
}

///|
/// Parse `?a=b&c=d` (leading `?` optional) into a map, decoding each value.
fn parse_query(search : String) -> Map[String, String] {
  let out : Map[String, String] = {}
  let s = if search.has_prefix("?") { search[1:].to_owned() } else { search }
  if s == "" {
    return out
  }
  for pair in s.split("&") {
    let p = pair.to_owned()
    if p == "" {
      continue
    }
    match p.split_once("=") {
      Some((k, v)) => out[uri_decode(k.to_owned())] = uri_decode(v.to_owned())
      None => out[uri_decode(p)] = ""
    }
  }
  out
}

///|
/// Write the { story, focus, filter } snapshot into the URL query string
/// (omitting empty keys) and push or replace the history entry. Built as a
/// string and handed to history.pushState — no URL/URLSearchParams constructor,
/// which `mizchi/js/core` doesn't expose on wasm-gc.
fn write_url(m : Map[String, @tutuca.Value], push : Bool) -> Unit {
  let parts : Array[String] = []
  for k in ["story", "focus", "filter"] {
    let v = match m.get(k) {
      Some(Str(s)) => s
      _ => ""
    }
    if v != "" {
      parts.push("\{k}=\{uri_encode(v)}")
    }
  }
  let g = @core.global_this()
  let path = g._get("location")._get("pathname").to_string()
  let url = if parts.is_empty() { path } else { path + "?" + parts.join("&") }
  let verb = if push { "pushState" } else { "replaceState" }
  let _ = g
    ._get("history")
    ._call(verb, [@core.null(), @core.any(""), @core.any(url)])

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
  let app = try! @sbui.mount(
    sections,
    root,
    opts,
    lint=lint_text,
    url_handlers=url_request_handlers(),
  )
  current_app.val = Some(app)
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

///|
/// Called from JS on `popstate` (Back/Forward). Re-sends `init` so the shell
/// re-reads the URL and restores the selection/filter/focus for the new entry.
/// Programmatic push/replaceState don't fire popstate, so this only runs on
/// real navigation — the same guard the JS storybook relies on.
pub fn on_popstate() -> Unit {
  match current_app.val {
    Some(app) => app.send_at_root("init")
    None => ()
  }
}
