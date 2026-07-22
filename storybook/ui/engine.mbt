// The storybook gallery as ONE generated tutuca component + the mount that
// wires every story's module into its own child scope.
//
// Layout: a left sidebar of grouped, clickable story titles (with a fuzzy
// filter box and a collapse toggle) drives a single `active` string field;
// each story has a `@show`-gated pane that renders its pre-built instance via
// `<x render=".sN">` (resolved by component id, so a foreign-scope instance
// renders fine) plus a collapsible Lint panel and a "focus" button. Focus mode
// (`.focus`/`.focusValue`) shows one story fullscreen. Selection, the filter,
// and the focused story sync to the URL query string through the host's
// `persistState`/`loadState` request handlers (see demo/storybook_wasm), so a
// gallery link reopens on the same story — the same design the JS storybook
// uses (src/storybook/mount.js).
//
// WHY NOT A TYPED STATE STRUCT: the shell's field set depends on the section
// list (`sN`/`lN`/`vN` per story, `cK`/`gvK` per section) — no struct can
// express a variable field set. The shell is therefore the framework's
// dynamic escape hatch in action: a `Component::for_type` component whose
// instances are the hand-written ShellInst Obj below.

///|
/// Minimal HTML text escape for titles/section labels injected into the view.
fn esc(s : String) -> String {
  s
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
}

///|
/// Escape a single-quoted attribute-value fragment (story ids interpolated into
/// `@on.click="onSelect '<id>'"` etc.). Ids are slugs today, but escaping keeps
/// the generator honest if a title-derived id ever carries a quote.
fn esc_attr(s : String) -> String {
  esc(s).replace(old="'", new="&#39;")
}

///|
/// Default lint callback: no findings. Hosts pass cli's check_component-backed
/// formatter to fill the Lint panel.
fn no_lint(_c : @component.Component) -> String {
  ""
}

///|
/// The margaui palette names offered by the theme switcher, mirroring
/// `margaui/dist/themes/*.css` (the JS storybook's MARGAUI_THEMES). Switching a
/// theme is just flipping `document.documentElement.dataset.theme`; the host's
/// `applyTheme` handler loads the palette stylesheet on demand (light/dark ship
/// in margaui's theme.css). Data, not a dependency — nothing imports margaui.
fn margaui_themes() -> Array[String] {
  [
    "light", "dark", "abyss", "acid", "aqua", "autumn", "black", "bumblebee", "business",
    "caramellatte", "cmyk", "coffee", "corporate", "cupcake", "cyberpunk", "dim",
    "dracula", "emerald", "fantasy", "forest", "garden", "halloween", "lemonade",
    "lofi", "luxury", "night", "nord", "pastel", "retro", "silk", "sunset", "synthwave",
    "valentine", "winter", "wireframe",
  ]
}

///|
/// The per-gallery metadata the handlers close over, aligned with the global
/// story index N used for the `sN`/`vN` fields. `comp` is wired right after
/// the Component is built.
priv struct ShellSpec {
  mut comp : @component.Component?
  filter_text : Array[String]
  sec_of : Array[Int]
  id_to_field : Map[String, String]
  init_fields : Array[String]
  num_sections : Int
}

///|
/// The gallery instance: a plain COW fields map behind the Obj trait — the
/// hand-written analogue of what typed components generate from their state
/// struct, for the one component whose fields are data-driven.
priv struct ShellInst {
  spec : ShellSpec
  fields : Map[String, @tutuca.Value]
}

///|
fn ShellInst::get(self : ShellInst, name : String) -> @tutuca.Value {
  self.fields.get(name).unwrap_or(Null)
}

///|
fn ShellInst::set(
  self : ShellInst,
  name : String,
  v : @tutuca.Value,
) -> ShellInst {
  let fields = self.fields.copy()
  fields[name] = v
  { spec: self.spec, fields }
}

///|
fn ShellInst::to_value(self : ShellInst) -> @tutuca.Value {
  Obj(self)
}

///|
/// Read a string field, defaulting to "" for any non-string (or missing) value.
fn str_field(inst : ShellInst, name : String) -> String {
  inst.get(name).str()
}

///|
/// Read a string out of an optional Value (a URLSearchParams lookup result),
/// defaulting to "".
fn str_of(v : @tutuca.Value?) -> String {
  match v {
    Some(Str(s)) => s
    _ => ""
  }
}

///|
/// Assemble the URL snapshot the host persists: the current selection, focus,
/// and filter, with any one of them overridden by the change the calling
/// handler is about to make (`self` is still the pre-change instance).
/// `theme` is deliberately absent from the base snapshot: the host merges these
/// keys into the existing query string, so omitting `theme` leaves an
/// already-chosen `?theme=` alone (otherwise typing in the filter would drop
/// it). Only `onSelectTheme` passes it, adding the key.
fn snapshot(
  inst : ShellInst,
  story? : String,
  focus? : String,
  filter? : String,
  theme? : String,
) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = {
    "story": Str(story.unwrap_or(str_field(inst, "active"))),
    "focus": Str(focus.unwrap_or(str_field(inst, "focus"))),
    "filter": Str(filter.unwrap_or(str_field(inst, "filter"))),
  }
  match theme {
    Some(t) => m["theme"] = Str(t)
    None => ()
  }
  Map(m)
}

///|
/// Subsequence match, bounded so a long query can't match by scattering its
/// characters across an unrelated string. A direct substring always matches;
/// otherwise the shortest window of the target that contains the query as a
/// subsequence must fit a small, query-scaled gap budget. Port of the JS
/// storybook's fuzzyMatch (src/storybook/components.js).
pub fn fuzzy_match(query : String, target : String) -> Bool {
  let q = query.to_lower().trim().to_owned()
  if q == "" {
    return true
  }
  let t = target.to_lower()
  if t.contains(q) {
    return true
  }
  let qc = q.to_array()
  let tc = t.to_array()
  // Allowed total gap grows slowly with length: len 3 -> +1, len 6 -> +3.
  let half = qc.length() / 2
  let budget = qc.length() + (if half > 1 { half } else { 1 })
  for start in 0..<tc.length() {
    if tc[start] != qc[0] {
      continue
    }
    let mut qi = 1
    let mut ti = start + 1
    while ti < tc.length() && qi < qc.length() {
      if tc[ti] == qc[qi] {
        qi = qi + 1
      }
      ti = ti + 1
    }
    if qi == qc.length() && ti - start <= budget {
      return true
    }
  }
  false
}

///|
/// Recompute sidebar visibility from `filter` AND each section's collapse state
/// (`cK`): a row `vN` shows when it passes the filter and its group is open; a
/// header `gvK` shows when any of its rows match the filter (ignoring collapse,
/// so a collapsed group that still matches stays visible to be reopened). An
/// empty filter shows every open group's rows.
fn apply_filter(inst : ShellInst, filter : String) -> ShellInst {
  let spec = inst.spec
  let mut out = inst.set("filter", Str(filter))
  let active = filter != ""
  let sec_any = Array::make(spec.num_sections, false)
  let collapsed = Array::make(spec.num_sections, false)
  for k in 0..<spec.num_sections {
    collapsed[k] = out.get("c\{k}").bool()
  }
  for i in 0..<spec.filter_text.length() {
    let m = !active || fuzzy_match(filter, spec.filter_text[i])
    if m {
      sec_any[spec.sec_of[i]] = true
    }
    out = out.set("v\{i}", Bool(m && !collapsed[spec.sec_of[i]]))
  }
  for k in 0..<spec.num_sections {
    out = out.set("gv\{k}", Bool(!active || sec_any[k]))
  }
  out
}

///|
impl @tutuca.Obj for ShellInst with fn component_id(self) {
  match self.spec.comp {
    Some(c) => Some(c.id)
    None => None
  }
}

///|
impl @tutuca.Obj for ShellInst with fn obj_field(self, name) {
  self.fields.get(name)
}

///|
impl @tutuca.Obj for ShellInst with fn obj_with_field(self, name, v) {
  if self.fields.contains(name) {
    Some(self.set(name, v).to_value())
  } else {
    None
  }
}

///|
impl @tutuca.Obj for ShellInst with fn obj_eq(self, other) {
  let my_id = match self.spec.comp {
    Some(c) => Some(c.id)
    None => None
  }
  if other.component_id() != my_id {
    return false
  }
  for k, v in self.fields {
    if other.obj_field(k) != Some(v) {
      return false
    }
  }
  true
}

///|
impl @tutuca.Obj for ShellInst with fn obj_debug(self) {
  "Storybook{active: \{str_field(self, "active")}}"
}

///|
/// Every event/message handler of the gallery, dispatched by (bucket, name).
/// The bodies mirror the JS storybook's mount.js handlers 1:1.
impl @tutuca.Obj for ShellInst with fn obj_handler(self, bucket, name) {
  let done = (inst : ShellInst) => Some(inst.to_value() as &@tutuca.PathNode)
  match (bucket, name) {
    (Input, "toggleSidebarCollapsed") =>
      Some(
        Handler((_args, _ctx) => {
          done(
            self.set(
              "sidebarCollapsed",
              Bool(!self.get("sidebarCollapsed").is_truthy()),
            ),
          )
        }),
      )
    // Sidebar filter: recompute row/header visibility and persist the filter.
    (Input, "onFilter") =>
      Some(
        Handler((args, ctx) => {
          let value = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.request(
            "persistState",
            [snapshot(self, filter=value), Bool(false)],
            @tutuca.RequestOpts::new(),
          )
          done(apply_filter(self, value))
        }),
      )
    // Collapse/expand a group in place (no URL change, matching the JS
    // storybook): flip its `cK` flag, then recompute so its rows hide/show
    // under the current filter.
    (Input, "onToggleSection") =>
      Some(
        Handler((args, _ctx) => {
          let k = match args {
            [Num(n), ..] => n.to_int()
            _ => -1
          }
          if k < 0 || k >= self.spec.num_sections {
            return done(self)
          }
          let out = self.set("c\{k}", Bool(!self.get("c\{k}").bool()))
          done(apply_filter(out, str_field(out, "filter")))
        }),
      )
    (Input, "onClearFilter") =>
      Some(
        Handler((_args, ctx) => {
          ctx.request(
            "persistState",
            [snapshot(self, filter=""), Bool(false)],
            @tutuca.RequestOpts::new(),
          )
          done(apply_filter(self, ""))
        }),
      )
    // Select a section pane; push a history entry so Back returns to the
    // prior story.
    (Input, "onSelect") =>
      Some(
        Handler((args, ctx) => {
          let id = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.request(
            "persistState",
            [snapshot(self, story=id), Bool(true)],
            @tutuca.RequestOpts::new(),
          )
          done(self.set("active", Str(id)))
        }),
      )
    (Input, "onFocusStory") =>
      Some(
        Handler((args, ctx) => {
          let id = match args {
            [Str(v), ..] => v
            _ => ""
          }
          match self.spec.id_to_field.get(id) {
            Some(fld) => {
              ctx.request(
                "persistState",
                [snapshot(self, focus=id), Bool(true)],
                @tutuca.RequestOpts::new(),
              )
              done(self.set("focus", Str(id)).set("focusValue", self.get(fld)))
            }
            None => done(self)
          }
        }),
      )
    (Input, "onFocusClose") =>
      Some(
        Handler((_args, ctx) => {
          ctx.request(
            "persistState",
            [snapshot(self, focus=""), Bool(false)],
            @tutuca.RequestOpts::new(),
          )
          done(self.set("focus", Str("")).set("focusValue", Null))
        }),
      )
    // Switching the palette is a document effect (set data-theme, load the
    // stylesheet), so it goes out as a request the host owns; the field only
    // syncs the switcher's shown value. theme is added to the persisted
    // snapshot here (and only here) so it enters the URL.
    (Input, "onSelectTheme") =>
      Some(
        Handler((args, ctx) => {
          let value = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.request("applyTheme", [Str(value)], @tutuca.RequestOpts::new())
          ctx.request(
            "persistState",
            [snapshot(self, theme=value), Bool(false)],
            @tutuca.RequestOpts::new(),
          )
          done(self.set("theme", Str(value)))
        }),
      )
    // On init (and Back/Forward, when the host re-sends it) restore selection,
    // filter, and focus from the URL, then fan `init` out to the panes that
    // load data on init. loadState 404s harmlessly on hosts without URL
    // persistence (the error path keeps the defaults).
    (Receive, "init") =>
      Some(
        Handler((_args, ctx) => {
          ctx.request("loadState", [], @tutuca.RequestOpts::new())
          for f in self.spec.init_fields {
            ctx.send_at_path(ctx.path().concat([FieldStep(f)]), "init", [])
          }
          done(self)
        }),
      )
    (Response, "loadState") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            // success: the host returns { story, focus, filter, theme }. The
            // host already resolved+applied the theme (URL param, else OS
            // preference) on the document; storing it here only syncs the
            // switcher's shown value.
            [Map(state), ..] => {
              let story = str_of(state.get("story"))
              let focus = str_of(state.get("focus"))
              let filter = str_of(state.get("filter"))
              let theme = str_of(state.get("theme"))
              let mut out = self.set("theme", Str(theme))
              // Any story id selects its pane (renderable panes and lint
              // fixtures alike); an id that matches nothing just leaves every
              // pane hidden.
              if story != "" {
                out = out.set("active", Str(story))
              }
              out = apply_filter(out, filter)
              match self.spec.id_to_field.get(focus) {
                Some(fld) =>
                  out = out
                    .set("focus", Str(focus))
                    .set("focusValue", self.get(fld))
                None => ()
              }
              done(out)
            }
            // error / no state: keep the defaults set by mount
            _ => done(self)
          }
        }),
      )
    _ => None
  }
}

///|
/// Generate the gallery view + handler metadata + field defaults from the
/// grouped sections. Field naming (`sN`/`lN`/`vN`) follows the SAME nested
/// iteration order `mount` uses, so indices line up. `gvK` is per section
/// index K.
fn build_shell(
  sections : Array[@sb.Section],
) -> (@component.Component, ShellSpec, Map[String, @tutuca.Value]) {
  let defaults : Map[String, @tutuca.Value] = {
    "active": Str(""),
    "filter": Str(""),
    "focus": Str(""),
    "focusValue": Null,
    "sidebarCollapsed": Bool(false),
    "theme": Str(""),
  }
  // Metadata captured by the handlers, aligned with the global story index N:
  // the fuzzy-match haystack and the owning section index. `id_to_field` maps
  // a renderable story's id to its `sN` field (for focus).
  let filter_text : Array[String] = []
  let sec_of : Array[Int] = []
  let id_to_field : Map[String, String] = Map([])
  let init_fields : Array[String] = []
  let num_sections = sections.length()
  let sb = StringBuilder::new()
  sb.write_string("<div>")
  // --- focus overlay: one fullscreen story, rendered from `.focusValue` ---
  sb.write_string(
    "<div class=\"flex flex-col gap-3 p-4 min-h-screen\" @show=\"truthy? .focus\">",
  )
  sb.write_string(
    "<div class=\"flex justify-end\">" +
    "<button class=\"btn btn-ghost btn-sm\" @on.click=\"onFocusClose\">close</button></div>",
  )
  sb.write_string(
    "<div class=\"flex-1 overflow-y-auto\"><x render=\".focusValue\"></x></div>",
  )
  sb.write_string("</div>")
  // --- normal layout, hidden while a story is focused ---
  // `h-screen overflow-hidden` pins the shell to the viewport so the sidebar
  // list and the content pane each scroll on their own (min-h-screen grows with
  // content, which would scroll the whole page and never the entry list).
  sb.write_string(
    "<div class=\"flex h-screen overflow-hidden\" @hide=\"truthy? .focus\">",
  )
  // collapsed rail: a single button to bring the sidebar back
  sb.write_string(
    "<button class=\"btn btn-ghost btn-sm self-start m-2\" title=\"Show sections\"" +
    " @show=\".sidebarCollapsed\" @on.click=\"toggleSidebarCollapsed\">»</button>",
  )
  // sidebar: a fixed-height column — the header stays put, the entry list below
  // it scrolls.
  sb.write_string(
    "<aside class=\"w-64 shrink-0 border-r border-base-300 p-3 flex flex-col overflow-hidden\" @hide=\".sidebarCollapsed\">",
  )
  // Header row: collapse toggle, the filter box (fills the space the old
  // "Storybook" title used), and the theme switcher.
  sb.write_string("<div class=\"flex items-center gap-2 mb-3 shrink-0\">")
  sb.write_string(
    "<button class=\"btn btn-ghost btn-sm\" title=\"Hide sections\" @on.click=\"toggleSidebarCollapsed\">«</button>",
  )
  sb.write_string(
    "<input class=\"input input-sm flex-1 min-w-0\" type=\"search\" placeholder=\"Filter\"" +
    " :value=\".filter\" @on.input=\"onFilter value\" @on.keydown+cancel=\"onClearFilter\" />",
  )
  sb.write_string(
    "<select class=\"select select-sm w-auto\" title=\"Theme\" :value=\".theme\" @on.input=\"onSelectTheme value\">",
  )
  for name in margaui_themes() {
    sb.write_string("<option value=\"\{name}\">\{name}</option>")
  }
  sb.write_string("</select></div>")
  // scrollable entry list: takes the remaining sidebar height and scrolls when
  // the sections overflow it.
  sb.write_string("<div class=\"flex-1 overflow-y-auto -mr-1 pr-1\">")
  let mut idx = 0
  let mut sec_index = 0
  for sec in sections {
    sb.write_string("<div class=\"mb-3\" @show=\".gv\{sec_index}\">")
    // clickable group header: the caret reflects `.cK`, the click toggles it.
    sb.write_string(
      "<div class=\"text-xs font-semibold uppercase opacity-50 mb-1 flex items-center gap-1 cursor-pointer select-none hover:opacity-80\"" +
      " title=\"Collapse or expand\" @on.click=\"onToggleSection \{sec_index}\">" +
      "<span class=\"inline-block w-3\" @show=\".c\{sec_index}\">▸</span>" +
      "<span class=\"inline-block w-3\" @hide=\".c\{sec_index}\">▾</span>" +
      "<span class=\"grow\">\{esc(sec.title)}</span></div>",
    )
    for s in sec.stories {
      filter_text.push("\{s.title} \{s.section} \{s.description}")
      sec_of.push(sec_index)
      let id = esc_attr(s.id)
      let desc_html = if s.description == "" {
        ""
      } else {
        "<div class=\"text-xs opacity-60 truncate\">\{esc(s.description)}</div>"
      }
      sb.write_string(
        "<a id=\"nav-\{s.id}\" @show=\".v\{idx}\" title=\"\{esc_attr(s.description)}\"" +
        " @if.class=\"equals? .active '\{id}'\"" +
        " @then=\"'block px-2 py-1 rounded cursor-pointer bg-primary text-primary-content'\"" +
        " @else=\"'block px-2 py-1 rounded cursor-pointer hover:bg-base-200'\"" +
        " @on.click=\"onSelect '\{id}'\">" +
        "<div class=\"text-sm font-medium\">\{esc(s.title)}</div>\{desc_html}</a>",
      )
      idx = idx + 1
    }
    sb.write_string("</div>")
    sec_index = sec_index + 1
  }
  sb.write_string("</div>")
  sb.write_string("</aside>")
  // content panes
  sb.write_string("<main class=\"flex-1 p-4 overflow-y-auto\">")
  idx = 0
  for sec in sections {
    for s in sec.stories {
      defaults["s\{idx}"] = Null
      defaults["l\{idx}"] = Str("")
      defaults["v\{idx}"] = Bool(true)
      if s.renderable {
        id_to_field[s.id] = "s\{idx}"
        if s.init {
          init_fields.push("s\{idx}")
        }
      }
      let id = esc_attr(s.id)
      sb.write_string("<section @show=\"equals? .active '\{id}'\">")
      sb.write_string("<div class=\"flex justify-between items-start mb-1\">")
      sb.write_string("<h2 class=\"text-xl font-bold\">\{esc(s.title)}</h2>")
      if s.renderable {
        sb.write_string(
          "<button class=\"btn btn-ghost btn-xs\" title=\"Focus this story\"" +
          " @on.click=\"onFocusStory '\{id}'\">focus</button>",
        )
      }
      sb.write_string("</div>")
      sb.write_string(
        "<div class=\"text-xs opacity-50 mb-3\">\{esc(s.section)}</div>",
      )
      if s.renderable {
        sb.write_string(
          "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
          "<x render=\".s\{idx}\"></x></div>",
        )
      } else {
        sb.write_string(
          "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100 text-sm opacity-60\">" +
          "This is a lint fixture — see the Lint panel below.</div>",
        )
      }
      sb.write_string(
        "<details class=\"mt-3\"><summary class=\"cursor-pointer text-sm opacity-60\">Lint</summary>" +
        "<pre class=\"text-xs mt-2 whitespace-pre-wrap opacity-80\" @text=\".l\{idx}\"></pre></details>",
      )
      sb.write_string("</section>")
      idx = idx + 1
    }
  }
  sb.write_string("</main></div></div>")
  for k in 0..<num_sections {
    defaults["gv\{k}"] = Bool(true)
    // per-section collapse flag (groups start expanded)
    defaults["c\{k}"] = Bool(false)
  }
  let spec : ShellSpec = {
    comp: None,
    filter_text,
    sec_of,
    id_to_field,
    init_fields,
    num_sections,
  }
  let comp = @component.Component::for_type(
    name="Storybook",
    view=sb.to_string(),
  )
  spec.comp = Some(comp)
  (comp, spec, defaults)
}

///|
/// The gallery root component generated from the grouped sections (instances
/// are built by `mount`).
pub fn shell_component(sections : Array[@sb.Section]) -> @component.Component {
  build_shell(sections).0
}

///|
/// Mount the gallery on `root_node`: register the shell (and any host URL
/// persistence handlers) in the root scope, each story's module in its own
/// child scope, pre-build each story instance from that scope, seed them as the
/// shell's `sN` fields, and start the app. `url_handlers` supplies the
/// `persistState`/`loadState` request handlers (the wasm host wires them to the
/// browser history/location; native/test hosts pass none and the gallery runs
/// without URL sync).
pub fn[N : @vdom.DomWalk] mount(
  sections : Array[@sb.Section],
  root_node : N,
  opts : @vdom.RenderOpts[N],
  lint? : (@component.Component) -> String = no_lint,
  url_handlers? : Map[String, @component.RequestFn] = Map([]),
) -> @app.App[N] raise {
  let root_scope = @component.ComponentStack::new()
  let (shell, spec, fields) = build_shell(sections)
  root_scope.register_components([shell])
  if !url_handlers.is_empty() {
    root_scope.register_request_handlers(url_handlers)
  }
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      let child = root_scope.enter()
      child.register_components(s.module_.components)
      child.register_macros(s.module_.macros)
      child.register_request_handlers(s.module_.requests)
      if idx == 0 {
        fields["active"] = Str(s.id)
      }
      match child.lookup_component(s.root) {
        Some(comp) => {
          // lint fixtures are linted but never rendered (their views trip
          // rules on purpose); build an instance only for renderable stories.
          fields["s\{idx}"] = if s.renderable {
            comp.make(s.args)
          } else {
            Null
          }
          fields["l\{idx}"] = Str(lint(comp))
        }
        None => {
          fields["s\{idx}"] = Null
          fields["l\{idx}"] = Str("(root component '\{s.root}' not found)")
        }
      }
      idx = idx + 1
    }
  }
  let root_value = ShellInst::{ spec, fields }.to_value()
  let app = @app.App::new(root_scope, root_value, root_node, opts)
  app.start()
  // tutuca has no lifecycle: the host dispatches `init`, which the shell uses
  // to restore URL state and to fan `init` out to the panes that load data on
  // init (request-example, personal-site, …). Always sent so the URL restore
  // runs even when no story needs a data init.
  app.send_at_root("init")
  app
}
