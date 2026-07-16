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
      // Resolve+apply the starting theme (URL param, else the OS preference) so
      // margaui's dark palette shows when the OS is dark; return the resolved
      // name so the switcher displays it.
      let theme = resolve_theme(params.get("theme").unwrap_or(""))
      respond(
        Ok(
          Map({
            "story": get("story"),
            "focus": get("focus"),
            "filter": get("filter"),
            "theme": Str(theme),
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
    // Switch the margaui palette: load its stylesheet (if not bundled) and flip
    // document.documentElement's data-theme.
    "applyTheme": @component.RequestFn((args, respond) => {
      match args {
        [Str(name), ..] => apply_theme(name)
        _ => ()
      }
      respond(Ok(Null))
    }),
  }
}

///|
/// Where margaui publishes its per-palette stylesheets. light + dark ship in the
/// theme.css already on the page; the rest are fetched on first selection.
let theme_base_url : String = "https://marianoguerra.github.io/margaui/themes/"

///|
/// "dark" when the OS prefers a dark scheme, else "light".
fn os_theme() -> String {
  let mm = @core.global_this()._call("matchMedia", [
    @core.any("(prefers-color-scheme: dark)"),
  ])
  if @core.is_nullish(mm) {
    "light"
  } else if mm._get("matches").to_string() == "true" {
    "dark"
  } else {
    "light"
  }
}

///|
/// Load a palette's stylesheet once (light/dark are bundled, so skipped).
fn ensure_theme_link(name : String) -> Unit {
  if name == "light" || name == "dark" {
    return
  }
  let doc = @core.global_this()._get("document")
  let id = "tutuca-theme-\{name}"
  if !@core.is_nullish(doc._call("getElementById", [@core.any(id)])) {
    return
  }
  let link = doc._call("createElement", [@core.any("link")])
  link._set("rel", @core.any("stylesheet"))
  link._set("id", @core.any(id))
  link._set("href", @core.any("\{theme_base_url}\{name}.css"))
  let _ = doc._get("head")._call("append", [link])
}

///|
/// Apply a palette: ensure its stylesheet is loaded, then set data-theme (which
/// every margaui utility reads through var(--color-*)).
fn apply_theme(name : String) -> Unit {
  if name == "" {
    return
  }
  ensure_theme_link(name)
  let _ = @core.global_this()
    ._get("document")
    ._get("documentElement")
    ._call("setAttribute", [@core.any("data-theme"), @core.any(name)])
}

///|
/// Pick the starting theme — the URL param if present, else the OS preference —
/// apply it, and return the resolved name.
fn resolve_theme(from_url : String) -> String {
  let name = if from_url != "" { from_url } else { os_theme() }
  apply_theme(name)
  name
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
/// Merge the snapshot into the CURRENT query string — set non-empty keys, delete
/// empty ones, leave keys the snapshot doesn't mention (e.g. `theme` while the
/// filter changes) untouched — then push or replace the history entry. Built as
/// a string and handed to history.pushState (no URL/URLSearchParams constructor,
/// which `mizchi/js/core` doesn't expose on wasm-gc).
fn write_url(m : Map[String, @tutuca.Value], push : Bool) -> Unit {
  let g = @core.global_this()
  let cur = parse_query(g._get("location")._get("search").to_string())
  for k, v in m {
    let s = match v {
      Str(x) => x
      _ => ""
    }
    if s == "" {
      cur.remove(k)
    } else {
      cur[k] = s
    }
  }
  let parts : Array[String] = []
  for k, v in cur {
    parts.push("\{uri_encode(k)}=\{uri_encode(v)}")
  }
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
