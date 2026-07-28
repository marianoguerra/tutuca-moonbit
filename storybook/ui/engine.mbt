// The storybook gallery as ONE generated tutuca component + the mount that
// wires every story's module into its own child scope.
//
// Layout: a left sidebar of grouped, clickable story titles (with a fuzzy
// filter box and a collapse toggle) drives a single `active` string field;
// each story has a `@show`-gated pane that renders its pre-built instance via
// `<x render=".sN">` (resolved by component id, so a foreign-scope instance
// renders fine) plus a "focus" button. Focus mode
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
  /// Builds the per-story Instance tab. One Inspector for the whole gallery,
  /// so every explorer it makes resolves against the same registered
  /// components.
  insp : @inspector.Inspector
  /// The story components, for the explorer's Component tab. Wired in `mount`
  /// (the shell is built before the scope exists) and absent in a shell built
  /// for a test, which the explorer handles by showing the instance alone.
  mut comps : @component.Components?
}

///|
/// The Instance tab's content for one story instance: the inspector's
/// InstanceExplorer over it — its fields, and its component's definition.
///
/// This is what the schema work bought at the gallery level. The explorer used
/// to need the instance AND its descriptor handed in together, because a value
/// could not name its own fields; it reads the instance now, and the registry
/// is only for the Component tab beside it.
fn ShellSpec::explorer_of(
  self : ShellSpec,
  instance : @tutuca.Value,
) -> @tutuca.Value {
  guard instance is Obj(_) else { return Null }
  self.insp.explore_value(instance, comps?=self.comps)
}

///|
/// The gallery instance: a plain COW fields map behind the Obj trait — the
/// hand-written analogue of what typed components generate from their state
/// struct, for the one component whose fields are data-driven.
priv struct ShellInst {
  spec : ShellSpec
  fields : Map[String, @tutuca.Value]
  // Memoized `Obj(self)`, for the same reason TypedInstance memoizes it: the
  // seams downstream compare Values by IDENTITY, and each cast allocates a
  // fresh box, so an unchanged instance handed out twice would look like two
  // different ones to the transactor's root-swap check.
  mut boxed : @tutuca.Value?
}

///|
fn ShellInst::make(
  spec : ShellSpec,
  fields : Map[String, @tutuca.Value],
) -> ShellInst {
  { spec, fields, boxed: None }
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
  ShellInst::make(self.spec, fields)
}

///|
/// The instance as a Value — the SAME Value every time (see `boxed`).
fn ShellInst::to_value(self : ShellInst) -> @tutuca.Value {
  match self.boxed {
    Some(v) => v
    None => {
      let v : @tutuca.Value = Obj(self)
      self.boxed = Some(v)
      v
    }
  }
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
/// Copy-on-write write-through — and the seam that keeps the Instance tab
/// LIVE.
///
/// A story dispatch updates the leaf at `.s<N>`, and the path rebuilds the
/// spine THROUGH here. So this is where the story's successor instance first
/// exists, and rebuilding `i<N>` from it in the same successor is what makes
/// the explorer track the story rather than show the state as of the moment
/// the tab was opened. Only when that tab is the one on screen: a gallery has
/// ~50 stories, and an explorer nobody is looking at is pure cost.
///
/// One instance out, so no extra transaction and no chance of a rebuild loop.
impl @tutuca.Obj for ShellInst with fn obj_with_field(self, name, v) {
  guard self.fields.contains(name) else { return None }
  let next = self.set(name, v)
  guard story_index(name) is Some(idx) else { return Some(next.to_value()) }
  guard next.get("t\{idx}") is Str("instance") else {
    return Some(next.to_value())
  }
  Some(next.set("i\{idx}", self.spec.explorer_of(v)).to_value())
}

///|
/// `s12` -> 12, for any other field name None. The story panes address their
/// fields by index, and this is the one place that has to read one back.
fn story_index(name : String) -> Int? {
  guard name.length() > 1 && name[0] is 's' else { return None }
  let digits = name[1:].to_owned()
  for c in digits {
    if !(c is ('0'..='9')) {
      return None
    }
  }
  Some(@string.parse_int(digits)) catch {
    _ => None
  }
}

///|
/// The descriptor built alongside the view — STORED on the Component, so this
/// is a read and not a rebuild. It carries every `sN`/`vN`/`cK`/`gvK` name the
/// shell computed, which is what lets `obj_eq` and `obj_debug` come from
/// `@tutuca`'s schema-ranged defaults instead of being written here.
impl @tutuca.Obj for ShellInst with fn obj_schema(self) {
  match self.spec.comp {
    Some(c) => Some(c.schema)
    None => None
  }
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
    // Story | Instance for one pane. Switching TO the instance tab builds the
    // explorer (it is Null until then), which is also the only place it is
    // built from a cold start — `obj_with_field` only keeps a live one fresh.
    (Input, "onStoryTab") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, tab) = match args {
            [Num(n), Str(t), ..] => (n.to_int(), t)
            _ => (-1, "story")
          }
          guard idx >= 0 else { return done(self) }
          let next = self.set("t\{idx}", Str(tab))
          done(
            if tab == "instance" {
              next.set("i\{idx}", self.spec.explorer_of(self.get("s\{idx}")))
            } else {
              // dropped on the way out: an explorer is a whole component tree,
              // and a closed tab has no use for one.
              next.set("i\{idx}", Null)
            },
          )
        }),
      )
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
              // Any story id selects its pane (renderable panes and
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
      defaults["v\{idx}"] = Bool(true)
      // the per-story tab, and the explorer the Instance tab renders. `i<N>`
      // starts Null and is built the first time the tab is opened: a gallery
      // has ~50 stories and nobody is looking at 50 explorers.
      defaults["t\{idx}"] = Str("story")
      defaults["i\{idx}"] = Null
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
        // Story | Instance, per story. The Instance pane renders the
        // inspector's explorer over THIS story's live instance — `i<N>` is
        // rebuilt whenever `s<N>` is written (see obj_with_field), so it
        // tracks the story as you drive it.
        sb.write_string(
          "<div role=\"tablist\" class=\"tabs tabs-sm mb-2\">" +
          "<a role=\"tab\" class=\"tab story-tab\"" +
          " @if.class=\"equals? .t\{idx} 'story'\"" +
          " @then=\"'tab tab-active story-tab'\" @else=\"'tab story-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'story'\">Story</a>" +
          "<a role=\"tab\" class=\"tab instance-tab\"" +
          " @if.class=\"equals? .t\{idx} 'instance'\"" +
          " @then=\"'tab tab-active instance-tab'\" @else=\"'tab instance-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'instance'\">Instance</a>" +
          "</div>",
        )
        sb.write_string(
          "<div @show=\"equals? .t\{idx} 'story'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
          "<x render=\".s\{idx}\"></x></div>",
        )
        sb.write_string(
          "<div @show=\"equals? .t\{idx} 'instance'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".i\{idx}\"></x></div>",
        )
      } else {
        sb.write_string(
          "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100 text-sm opacity-60\">" +
          "This story is a deliberately-broken view fixture; it is listed but not rendered.</div>",
        )
      }
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
    insp: @inspector.Inspector::new(),
    comps: None,
  }
  // The shell's field set depends on the section list, which is why it is a
  // `for_type` component and not a typed-state one. Depending on a runtime
  // value is not the same as being unknown, though: by this point every field
  // name has been computed, so the descriptor is written from the same data
  // the view was.
  let field_names : Array[String] = []
  for name, _ in defaults {
    field_names.push(name)
  }
  field_names.sort_by((a, b) => a.lexical_compare(b))
  let comp = @component.Component::for_type(
    views={ "main": @anode.View::new("main", raw_view=sb.to_string()) },
    name="Storybook",
    schema=@component.SchemaInfo::new(
      name="Storybook",
      // The section list IS the shape, so it is what the fingerprint hashes.
      fingerprint="shell\{num_sections}x\{filter_text.length()}",
      fields=field_names.map(n => @component.FieldInfo::new(n, @tutuca.TyAny)),
      inputs=[
        "onClearFilter", "onFilter", "onFocusClose", "onFocusStory", "onSelect",
        "onSelectTheme", "onToggleSection",
      ],
      view_names=["main"],
    ),
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
  url_handlers? : Map[String, @component.RequestFn] = Map([]),
) -> @app.App[N] raise {
  let root_scope = @component.ComponentStack::new()
  let (shell, spec, fields) = build_shell(sections)
  root_scope.register_components([shell])
  // The registry is shared by id across every story's child scope, so this one
  // resolves any story instance the Instance tab is opened on — which is what
  // puts the Component tab beside the fields.
  spec.comps = Some(root_scope.comps)
  // The explorer the Instance tab renders is an instance of the INSPECTOR's
  // components, and `<x render=".iN">` resolves an instance through the
  // registry by component id — so an unregistered explorer renders as nothing
  // and the tab comes up blank. Registered in a scope of its own rather than
  // the root's, so ~35 inspector names (JsonObject, CompField, …) don't become
  // visible to every story that didn't register a component of that name.
  root_scope.enter().register_components(spec.insp.components())
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
        Some(comp) =>
          // deliberately-broken fixtures are listed but never rendered
          // (their views trip parse issues on purpose).
          fields["s\{idx}"] = if s.renderable {
            comp.make(s.args)
          } else {
            Null
          }
        None => fields["s\{idx}"] = Null
      }
      idx = idx + 1
    }
  }
  let root_value = ShellInst::make(spec, fields).to_value()
  let app = @app.App::new(root_scope, root_value, root_node, opts)
  app.start()
  // tutuca has no lifecycle: the host dispatches `init`, which the shell uses
  // to restore URL state and to fan `init` out to the panes that load data on
  // init (request-example, personal-site, …). Always sent so the URL restore
  // runs even when no story needs a data init.
  app.send_at_root("init")
  app
}
