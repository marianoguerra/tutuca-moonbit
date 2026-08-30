// The storybook gallery in a browser: everything the pure gallery cannot do.
//
// `mount` puts the whole thing on the page — the gallery, the URL/theme
// services, the DOM event bridge, the styles and the compiled margaui sheet —
// and the four entry points below are what a page's export list forwards to.
// A host package is then five one-line functions and a `link.exports` list.

///|
/// The mounted gallery app, stashed so the `on_popstate` and `refresh_margaui`
/// entry points can reach it. tutuca has no lifecycle, so — like the JS
/// storybook's `window.addEventListener("popstate", …)` — the host re-sends
/// `init`, which re-runs the shell's `loadState` restore.
///
/// One page mounts one gallery: a second `mount` replaces this.
let current_app : Ref[@app.App[@wdom.WasmNode]?] = { val: None, }

///|
/// Where margaui publishes its per-palette stylesheets. light + dark ship in
/// the theme.css already on the page; the rest are fetched on first selection.
///
/// A default rather than a constant: a gallery that self-hosts its palettes —
/// or offers only the two bundled ones — passes its own base to `mount`.
pub let default_theme_base_url : String = "https://marianoguerra.github.io/margaui/themes/"

///|
/// The browser-history request handlers wired into the gallery's root scope:
/// `loadState` reads the query string, `persistState` writes it, `applyTheme`
/// switches the palette. Here rather than in `storybook/ui` so the pure gallery
/// package never depends on the JS FFI — the same split as the JS storybook,
/// where mount.js owns the URL effects. The page's own services, on the LEX
/// leg.
///
/// A LIST per name, because that leg walks: a declining handler hands the
/// intent to the next one. These three never decline — a page that owns the
/// URL is the only thing that can answer for it — so each list has one entry.
/// A host with more to say adds its own names through `mount`'s `intents~`.
pub fn url_request_handlers(
  theme_base_url? : String = default_theme_base_url,
) -> Map[String, Array[@component.IntentFn]] {
  {
    "loadState": [
      IntentFn((_call, answer) => {
        let params = parse_query(
          @core.global_this()._get("location")._get("search").to_string(),
        )
        let get = fn(k : String) -> @tutuca.Value {
          Str(params.get(k).unwrap_or(""))
        }
        // Resolve+apply the starting theme (URL param, else the OS preference) so
        // margaui's dark palette shows when the OS is dark; return the resolved
        // name so the switcher displays it.
        let theme = resolve_theme(
          params.get("theme").unwrap_or(""),
          theme_base_url,
        )
        answer(
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
    ],
    "persistState": [
      IntentFn((call, answer) => {
        match call.args {
          [Map(m), push] => write_url(m, push is Bool(true))
          _ => ()
        }
        answer(Ok(Null))
      }),
    ],
    // Switch the margaui palette: load its stylesheet (if not bundled) and flip
    // document.documentElement's data-theme.
    "applyTheme": [
      IntentFn((call, answer) => {
        match call.args {
          [Str(name), ..] => apply_theme(name, theme_base_url)
          _ => ()
        }
        answer(Ok(Null))
      }),
    ],
  }
}

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
fn ensure_theme_link(name : String, base : String) -> Unit {
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
  link._set("href", @core.any("\{base}\{name}.css"))
  let _ = doc._get("head")._call("append", [link])
}

///|
/// Apply a palette: ensure its stylesheet is loaded, then set data-theme (which
/// every margaui utility reads through var(--color-*)).
fn apply_theme(name : String, base : String) -> Unit {
  if name == "" {
    return
  }
  ensure_theme_link(name, base)
  let _ = @core.global_this()
    ._get("document")
    ._get("documentElement")
    ._call("setAttribute", [@core.any("data-theme"), @core.any(name)])
}

///|
/// Pick the starting theme — the URL param if present, else the OS preference —
/// apply it, and return the resolved name.
fn resolve_theme(from_url : String, base : String) -> String {
  let name = if from_url != "" { from_url } else { os_theme() }
  apply_theme(name, base)
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
  let out : Map[String, String] = Map([])
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
/// Mount the gallery on `#<root_id>` and wire the page to it: the URL and theme
/// services, the DOM event bridge, the component styles, and the compiled
/// margaui sheet. None when the element is absent, which is the one failure a
/// page can actually fix.
///
/// `intents~` are the host's own request handlers, merged with the gallery's
/// URL services — a story that asks the page for something (`loadData`, a
/// clock) is answered from here.
pub fn mount(
  sections : Array[@sb.Section],
  root_id? : String = "app",
  themes? : Array[String] = @sbui.margaui_themes(),
  /// The tabs beside Story. NONE by default, and that is a linking decision
  /// rather than a taste one: this package imports no panel layer, so a page
  /// that wants stories and nothing else carries no inspector, no recorder and
  /// no fuzz driver in its wasm. `storybook/ui/panels/wasm`'s `all()` is the
  /// standard set, and asking for it is what pulls it in.
  panels? : @sbui.PanelSet[@wdom.WasmNode] = @sbui.PanelSet::none(),
  intents? : Map[String, Array[@component.IntentFn]] = Map([]),
  theme_base_url? : String = default_theme_base_url,
) -> @app.App[@wdom.WasmNode]? {
  let doc = @wglue.document()
  guard @wglue.element_by_id(doc, root_id) is Some(root) else {
    @tutuca.warn("storybook: no #\{root_id} element to mount on")
    return None
  }
  let handlers = url_request_handlers(theme_base_url~)
  for name, fns in intents {
    match handlers.get(name) {
      // the page's own handler goes AFTER the gallery's on the walking leg,
      // so a host cannot silently shadow the URL services it asked for
      Some(existing) => handlers[name] = existing + fns
      None => handlers[name] = fns
    }
  }
  let app = try! @sbui.mount(
    sections,
    root,
    @vdom.RenderOpts::new(doc),
    url_handlers=handlers,
    themes~,
    panels~,
  )
  current_app.val = Some(app)
  @wglue.install(app)
  @wglue.install_styles(app, doc)
  // compile the collected margaui class set (gallery chrome + every story's
  // classes) to CSS in MoonBit and inject it
  apply_margaui(app, doc)
  Some(app)
}

///|
/// Compile the collected margaui/Tailwind class set to CSS (via the MoonBit
/// marianoguerra/tailwindcss port) and inject it as <style id="margaui-css">.
/// Replaces the old page-side CDN margaui compile. index.html pre-places an
/// empty <style id="margaui-css"> early in <head> so the upsert keeps it ahead
/// of any lazily-loaded palette <link> in the cascade.
fn apply_margaui(app : @app.App[@wdom.WasmNode], doc : @wdom.WasmNode) -> Unit {
  let css = @css.compile_margaui(app.scope.comps.collect_classes()) catch {
    err => {
      @tutuca.warn("margaui compile failed: \{err}")
      return
    }
  }
  @wglue.inject_style(doc, "margaui-css", css)
}

///|
/// Recompile + reinject margaui CSS for the mounted gallery. No-op before
/// mount; kept as an export so a host can refresh the sheet after registering
/// views the initial compile did not see.
pub fn refresh_margaui() -> Unit {
  guard current_app.val is Some(app) else { return }
  apply_margaui(app, @wglue.document())
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
///
/// `before` gets first refusal on each event and says whether it consumed it —
/// the seam a panel layer needs, because while the Trace panel is waiting to be
/// pointed at, a click MEANS something else and letting it through as well
/// would drive the app with the click that was meant to point at it. Nothing
/// intercepts by default; `storybook/ui/panels/wasm`'s `on_event` is the
/// version that does.
pub fn on_event(
  ev : @core.Any,
  before? : (@wdom.WasmNode, String) -> Bool = (_node, _name) => false,
) -> Unit {
  @wglue.on_event(ev, before~)
}

///|
/// Called from JS on `popstate` (Back/Forward). Re-sends `init` so the shell
/// re-reads the URL and restores the selection/filter/focus for the new entry.
/// Programmatic push/replaceState don't fire popstate, so this only runs on
/// real navigation — the same guard the JS storybook relies on.
pub fn on_popstate() -> Unit {
  match current_app.val {
    Some(app) => app.send_at_root("init") |> ignore
    None => ()
  }
}

///|
/// The gallery this page mounted, for a panel layer that needs to reach it
/// from a DOM listener — the click interception above is the case. None before
/// `mount`.
pub fn current_gallery() -> @app.App[@wdom.WasmNode]? {
  current_app.val
}
