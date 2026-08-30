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
// gallery link reopens on the same story.
//
// WHY NOT A TYPED STATE STRUCT: the shell's field set depends on the section
// list (`sN`/`lN`/`vN` per story, `cK`/`gvK` per section) — no struct can
// express a variable field set. The shell is therefore the framework's
// dynamic escape hatch in action: a `Component::for_type` component whose
// instances are the hand-written ShellInst Obj below.
//
// WHAT IS NOT HERE: any panel. The tabs beside Story — the value explorer, the
// recorder, the fuzz driver — are `PanelDef`s handed in by the caller
// (`storybook/ui/panels` supplies the standard set), which is why this package
// imports neither the inspector nor the recorder nor the fuzz driver. The
// shell knows a panel by its key, its field prefix, and a closure that builds
// its value.

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
/// `margaui/dist/themes/*.css`. Switching a
/// theme is just flipping `document.documentElement.dataset.theme`; the host's
/// `applyTheme` handler loads the palette stylesheet on demand (light/dark ship
/// in margaui's theme.css). Data, not a dependency — nothing imports margaui.
///
/// The default for `mount`'s `themes~`. A gallery that ships two palettes, or
/// none, passes its own list instead.
pub fn margaui_themes() -> Array[String] {
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
  /// a renderable story's id to the view it declared, for focus mode (the
  /// panes carry their own `pvN` field; the overlay renders `.focusValue`
  /// and so needs the name handed to it)
  view_of : Map[String, String]
  init_fields : Array[String]
  num_sections : Int
  /// The tabs beside Story, in the order they are drawn. The shell resolves a
  /// tab key to a field prefix and a builder through this and nothing else.
  panels : Array[PanelDef]
  /// The gallery-wide fields the panels declared, and the only names
  /// `setFields` will write.
  panel_fields : Map[String, @tutuca.Value]
}

///|
/// The panel a tab key names, or None.
fn ShellSpec::panel_of(self : ShellSpec, key : String) -> PanelDef? {
  for p in self.panels {
    if p.key == key {
      return Some(p)
    }
  }
  None
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
  { spec, fields, boxed: None, }
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
/// subsequence must fit a small, query-scaled gap budget.
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
  guard next.get("t\{idx}") is Str(tab) else { return Some(next.to_value()) }
  guard self.spec.panel_of(tab) is Some(p) && p.live && p.build is Some(build) else {
    return Some(next.to_value())
  }
  Some(next.set("\{p.field}\{idx}", build(v, n => next.get(n))).to_value())
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
impl @tutuca.Obj for ShellInst with fn obj_handler(self, bucket, name) {
  self.handler_for(bucket, name)
}

///|
fn ShellInst::handler_for(
  self : ShellInst,
  bucket : @tutuca.HandlerBucket,
  name : String,
) -> @tutuca.Handler? {
  let done = (inst : ShellInst) => Some(inst.to_value())
  match (bucket, name) {
    (Receive, "toggleSidebarCollapsed") =>
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
    (Receive, "onFilter") =>
      Some(
        Handler((args, ctx) => {
          let value = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.intent(
            "persistState",
            [snapshot(self, filter=value), Bool(false)],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          done(apply_filter(self, value))
        }),
      )
    // Collapse/expand a group in place (no URL change, matching the JS
    // storybook): flip its `cK` flag, then recompute so its rows hide/show
    // under the current filter.
    // Switching tabs is the only place a panel is built from cold.
    //
    // Three rules, all read off the PanelDef rather than written here: a panel
    // with a builder is built the first time its tab is opened (a gallery has
    // ~50 stories, and building 50 explorers nobody asked for is pure cost); a
    // panel that does not `keep` is dropped on the way out; and a panel the
    // host pushes has no builder at all, so opening its tab shows whatever the
    // host last sent.
    (Receive, "onStoryTab") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, tab) = match args {
            [Num(n), Str(t), ..] => (n.to_int(), t)
            _ => (-1, "story")
          }
          guard idx >= 0 else { return done(self) }
          let mut next = self.set("t\{idx}", Str(tab))
          for p in self.spec.panels {
            let field = "\{p.field}\{idx}"
            if p.key == tab {
              if p.build is Some(build) && next.get(field) is Null {
                next = next.set(
                  field,
                  build(self.get("s\{idx}"), n => self.get(n)),
                )
              }
            } else if !p.keep {
              next = next.set(field, Null)
            }
          }
          done(next)
        }),
      )
    // The shell raising an intent on a panel's behalf.
    //
    // A panel's own effects are the HOST's — a document listener is not
    // something a component can install — but only a component can raise an
    // intent, so the glue sends this and the shell forwards it. The shell does
    // not know what `traceCandidates` means, and does not need to.
    (Receive, "panelIntent") =>
      Some(
        Handler((args, ctx) => {
          match args {
            [Str(name), payload, ..] =>
              ctx.intent(name, [payload], @tutuca.IntentOpts::new(route=[Lex]))
            _ => ()
          }
          done(self)
        }),
      )
    // The host writing a rebuilt panel back in.
    //
    // The one direction that has to exist: a recorder lives on the transactor
    // and a fuzz run remounts components, neither of which a component can
    // reach — so the panel a pane shows is a value the host hands down, and
    // this is the door it comes through. Addressed by story index and panel
    // key, because the host knows both and nothing else about where the pane
    // lives.
    (Receive, "setPanel") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, key, panel) = match args {
            [Num(n), Str(k), p, ..] => (n.to_int(), k, p)
            _ => (-1, "", (Null : @tutuca.Value))
          }
          guard idx >= 0 && self.spec.panel_of(key) is Some(p) else {
            return done(self)
          }
          done(self.set("\{p.field}\{idx}", panel))
        }),
      )
    // Put a story's instance back to what it was mounted with.
    //
    // The one write the host does to a story rather than to a panel, and it
    // exists because a reset has to be EXACT: rewinding a component by sending
    // it the reverse of what it received is not a thing that exists, so the
    // only honest reset is the value the gallery built at mount.
    (Receive, "setStoryValue") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, v) = match args {
            [Num(n), value, ..] => (n.to_int(), value)
            _ => (-1, (Null : @tutuca.Value))
          }
          guard idx >= 0 else { return done(self) }
          done(self.set("s\{idx}", v))
        }),
      )
    // A panel's gallery-wide knobs, written back so the shell and the panel
    // cannot disagree about what the rows underneath were drawn at. Only
    // fields a PanelDef declared: this is a door for the panel layer, not a
    // general write into the shell.
    (Receive, "setFields") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Map(m), ..] => {
              let mut out = self
              for name, v in m {
                if self.spec.panel_fields.contains(name) {
                  out = out.set(name, v)
                }
              }
              done(out)
            }
            _ => done(self)
          }
        }),
      )
    (Receive, "onToggleSection") =>
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
    (Receive, "onClearFilter") =>
      Some(
        Handler((_args, ctx) => {
          ctx.intent(
            "persistState",
            [snapshot(self, filter=""), Bool(false)],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          done(apply_filter(self, ""))
        }),
      )
    // Select a section pane; push a history entry so Back returns to the
    // prior story.
    (Receive, "onSelect") =>
      Some(
        Handler((args, ctx) => {
          let id = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.intent(
            "persistState",
            [snapshot(self, story=id), Bool(true)],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          done(self.set("active", Str(id)))
        }),
      )
    (Receive, "onFocusStory") =>
      Some(
        Handler((args, ctx) => {
          let id = match args {
            [Str(v), ..] => v
            _ => ""
          }
          match self.spec.id_to_field.get(id) {
            Some(fld) => {
              ctx.intent(
                "persistState",
                [snapshot(self, focus=id), Bool(true)],
                @tutuca.IntentOpts::new(route=[Lex]),
              )
              done(
                self
                .set("focus", Str(id))
                .set("focusValue", self.get(fld))
                .set("focusView", Str(self.spec.view_of.get(id).unwrap_or(""))),
              )
            }
            None => done(self)
          }
        }),
      )
    (Receive, "onFocusClose") =>
      Some(
        Handler((_args, ctx) => {
          ctx.intent(
            "persistState",
            [snapshot(self, focus=""), Bool(false)],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          done(
            self
            .set("focus", Str(""))
            .set("focusValue", Null)
            .set("focusView", Str("")),
          )
        }),
      )
    // Switching the palette is a document effect (set data-theme, load the
    // stylesheet), so it goes out as a request the host owns; the field only
    // syncs the switcher's shown value. theme is added to the persisted
    // snapshot here (and only here) so it enters the URL.
    (Receive, "onSelectTheme") =>
      Some(
        Handler((args, ctx) => {
          let value = match args {
            [Str(v), ..] => v
            _ => ""
          }
          ctx.intent(
            "applyTheme",
            [Str(value)],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          ctx.intent(
            "persistState",
            [snapshot(self, theme=value), Bool(false)],
            @tutuca.IntentOpts::new(route=[Lex]),
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
          ctx.intent("loadState", [], @tutuca.IntentOpts::new(route=[Lex]))
          for f in self.spec.init_fields {
            ctx.send_at_path(ctx.path().concat([FieldStep(f)]), "init", [])
          }
          done(self)
        }),
      )
    // The ANSWER, which is an ordinary message now — same bucket as `init`
    // above, and named for the outcome rather than for the request. `loadState`
    // names no outcomes in its opts, so the runtime derives them: `<name>Ok`.
    //
    // A host with no URL persistence answers nothing, the route runs out, and
    // this component declares no `loadStateUnhandled` — so nothing arrives and
    // the defaults stand, which is what the paragraph above always meant by
    // "404s harmlessly".
    (Receive, "loadStateOk") =>
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
                    .set(
                      "focusView",
                      Str(self.spec.view_of.get(focus).unwrap_or("")),
                    )
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
  themes~ : Array[String],
  panels_in~ : Array[PanelDef],
  panel_fields~ : Map[String, @tutuca.Value],
) -> (@component.Component, ShellSpec, Map[String, @tutuca.Value]) {
  let defaults : Map[String, @tutuca.Value] = {
    "active": Str(""),
    "filter": Str(""),
    "focus": Str(""),
    "focusValue": Null,
    "focusView": Str(""),
    "sidebarCollapsed": Bool(false),
    "theme": Str(""),
    // The Fuzz tab's knobs, on the shell rather than in the panel: the panel
    // is rebuilt by the host on every change, so a knob that lived only there
    // would be read back from the thing that is about to be replaced. They are
    // gallery-wide on purpose — a seed is what you carry from one story to the
    // next when you are looking for the same shape of bug.
  }
  // The panels' own gallery-wide fields. Theirs rather than the shell's — a
  // fuzz seed is what you carry from one story to the next, and the shell has
  // no idea what one is.
  for name, v in panel_fields {
    defaults[name] = v
  }
  // Metadata captured by the handlers, aligned with the global story index N:
  // the fuzzy-match haystack and the owning section index. `id_to_field` maps
  // a renderable story's id to its `sN` field (for focus).
  // A panel whose field prefix would collide is dropped rather than allowed to
  // overwrite: `s`/`v`/`t`/`c`/`gv`/`pv` are the shell's own, and two panels
  // sharing a prefix would each show the other's value.
  let reserved = ["s", "v", "t", "c", "gv", "pv"]
  let seen_fields : Array[String] = []
  let panels : Array[PanelDef] = []
  for p in panels_in {
    if reserved.contains(p.field) || seen_fields.contains(p.field) {
      @tutuca.warn(
        "storybook: panel '\{p.key}' wants field prefix '\{p.field}', which is taken — dropping it",
      )
      continue
    }
    seen_fields.push(p.field)
    panels.push(p)
  }
  let filter_text : Array[String] = []
  let sec_of : Array[Int] = []
  let id_to_field : Map[String, String] = Map([])
  let view_of : Map[String, String] = Map([])
  let init_fields : Array[String] = []
  let num_sections = sections.length()
  let sb = StringBuilder()
  sb.write_string("<div>")
  // --- focus overlay: one fullscreen story, rendered from `.focusValue` ---
  sb.write_string(
    "<div class=\"flex flex-col gap-3 p-4 min-h-screen\" @show=\"truthy? .focus\">",
  )
  sb.write_string(
    "<div class=\"flex justify-end\">" +
    "<button class=\"btn btn-ghost btn-sm\" @on.click=\"onFocusClose\">close</button></div>",
  )
  // `@push-view` falls back to `main` for a name it cannot find, so the empty
  // default is exactly "the component's own view resolution".
  sb.write_string(
    "<div class=\"flex-1 overflow-y-auto\" @push-view=\".focusView\">" +
    "<x render=\".focusValue\"></x></div>",
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
    " :value=\".filter\" @on.input=\"onFilter e.value\" @on.keydown+cancel=\"onClearFilter\" />",
  )
  sb.write_string(
    "<select class=\"select select-sm w-auto\" title=\"Theme\" :value=\".theme\" @on.input=\"onSelectTheme e.value\">",
  )
  for name in themes {
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
        " @if.class=\".active is '\{id}'\"" +
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
      defaults["t\{idx}"] = Str("story")
      // One field per declared panel, all starting Null: a panel is built the
      // first time its tab is opened, because a gallery has ~50 stories and
      // nobody is looking at 50 explorers.
      for p in panels {
        defaults["\{p.field}\{idx}"] = Null
      }
      if s.renderable {
        id_to_field[s.id] = "s\{idx}"
        if s.view != "" {
          view_of[s.id] = s.view
        }
        if s.init {
          init_fields.push("s\{idx}")
        }
      }
      // A story that names a view renders under it, in the Story pane and the
      // Fuzz pane alike — they show the same instance and must not disagree
      // about which view of it. A story with no view needs no wrapper.
      let (pv_open, pv_close) = if s.view == "" {
        ("", "")
      } else {
        defaults["pv\{idx}"] = Str(s.view)
        ("<div @push-view=\".pv\{idx}\">", "</div>")
      }
      let id = esc_attr(s.id)
      sb.write_string("<section @show=\".active is '\{id}'\">")
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
        // The tab strip, from the panel table. One tab is no tabs: with no
        // panels declared the story pane IS the pane.
        if panels.length() > 0 {
          sb.write_string("<div role=\"tablist\" class=\"tabs tabs-sm mb-2\">")
          let strip : Array[(String, String)] = [("story", "Story")]
          for p in panels {
            strip.push((p.key, p.label))
          }
          for tab in strip {
            let (key, label) = tab
            sb.write_string(
              "<a role=\"tab\" class=\"tab \{key}-tab\"" +
              " @if.class=\".t\{idx} is '\{key}'\"" +
              " @then=\"'tab tab-active \{key}-tab'\" @else=\"'tab \{key}-tab'\"" +
              " @on.click=\"onStoryTab \{idx} '\{key}'\">\{label}</a>",
            )
          }
          sb.write_string("</div>")
        }
        sb.write_string(
          "<div @show=\".t\{idx} is 'story'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
          "\{pv_open}<x render=\".s\{idx}\"></x>\{pv_close}</div>",
        )
        // A panel pane is `<x render=".<field><N>">` and nothing else — the
        // shell renders a value it did not build and cannot read.
        //
        // `with_story` is the one variation, and the Fuzz tab is why it
        // exists: a run is WATCHED. The whole reason to drive generated
        // dispatches in a browser rather than under `moon test` is that the
        // component is on screen while they land, so that pane shows the same
        // `s<N>` the Story tab does — one instance, not a second mount, which
        // is also what makes the rows and the picture agree.
        for p in panels {
          if p.with_story {
            sb.write_string(
              "<div @show=\".t\{idx} is '\{p.key}'\" class=\"flex flex-col gap-2\">" +
              "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
              "\{pv_open}<x render=\".s\{idx}\"></x>\{pv_close}</div>" +
              "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
              "<x render=\".\{p.field}\{idx}\"></x></div></div>",
            )
          } else {
            sb.write_string(
              "<div @show=\".t\{idx} is '\{p.key}'\"" +
              " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
              "<x render=\".\{p.field}\{idx}\"></x></div>",
            )
          }
        }
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
    view_of,
    init_fields,
    num_sections,
    panels,
    panel_fields,
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
      fields=field_names.map(n => @component.FieldInfo::new(n, TyAny)),
      view_handlers=[
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
/// Warn about an arg holding a component instance the story's own scope cannot
/// resolve. A `Component` carries an id bound to the scope it was registered
/// in, so such an instance renders as nothing — a blank slot inside an
/// otherwise live story, with no error anywhere.
///
/// Projected stories cannot hit this: an `ExampleDef`'s args are built inside
/// the module that registers the components they name. Hand-written ones can,
/// which is why the check is here and not in `project.mbt`.
fn warn_unresolved_args(
  s : @sb.Story,
  scope : @component.ComponentStack,
) -> Unit {
  for name, value in s.args {
    if value is Obj(_) && scope.comps.get_comp_for(value) is None {
      @tutuca.warn(
        "storybook: story '\{s.id}' arg '\{name}' holds an instance no component in module '\{s.module_.name}' can render",
      )
    }
  }
}

///|
/// Mount the gallery on `root_node`: register the shell (and any host URL
/// persistence handlers) in the root scope, each story's module in its own
/// child scope, pre-build each story instance from that scope, seed them as the
/// shell's `sN` fields, and start the app.
///
/// `url_handlers` supplies the `persistState`/`loadState` request handlers (the
/// wasm host wires them to the browser history/location; native/test hosts pass
/// none and the gallery runs without URL sync). `panels` supplies the tabs
/// beside Story — `storybook/ui/panels` builds the standard set; the default is
/// none, and a gallery with none is a gallery rather than a debugger.
pub fn[N : @vdom.DomWalk] mount(
  sections : Array[@sb.Section],
  root_node : N,
  opts : @vdom.RenderOpts[N],
  url_handlers? : Map[String, Array[@component.IntentFn]] = Map([]),
  /// The palettes the theme switcher offers. The default is margaui's, which
  /// is what the compiled stylesheet carries; a gallery that ships two
  /// palettes passes two.
  themes? : Array[String] = margaui_themes(),
  /// The per-story tabs. Everything this package knows about a panel is in
  /// here: a key, a label, a field prefix and a closure.
  panels? : PanelSet[N] = PanelSet::none(),
) -> @app.App[N] raise {
  let root_scope = @component.ComponentStack::new()
  let (shell, spec, fields) = build_shell(
    sections,
    themes~,
    panels_in=panels.defs,
    panel_fields=panels.fields,
  )
  root_scope.register_components([shell])
  // A panel's own components — the explorer's tree, the recorder bar — are
  // instances like any other, and `<x render=".iN">` resolves one through the
  // registry by component id, so an unregistered panel renders as nothing.
  // Registered in a scope of their own rather than the root's, so ~35 names
  // (JsonObject, CompField, …) don't become visible to every story that didn't
  // register a component of that name.
  if panels.components.length() > 0 {
    root_scope.enter().register_components(panels.components)
  }
  if !url_handlers.is_empty() {
    root_scope.register_intent_handlers(url_handlers)
  }
  // A panel's intents, answered by the panel layer rather than here: a
  // recorder lives on the transactor and a run remounts components, and this
  // package can reach neither. They are registered before the app exists and
  // close over a slot `attach` fills below.
  if !panels.intents.is_empty() {
    root_scope.register_intent_handlers(panels.intents)
  }
  let mut idx = 0
  // Kept rather than dropped: a panel that rebuilds a story's value from a
  // snapshot needs the scope its components are registered in, and that scope
  // exists only here. See `story_scope`.
  story_scopes.val = []
  for sec in sections {
    for s in sec.stories {
      let child = root_scope.enter()
      story_scopes.val.push(child)
      child.register_components(s.module_.components)
      child.register_macros(s.module_.macros)
      child.register_intent_handlers(s.module_.intents)
      if idx == 0 {
        fields["active"] = Str(s.id)
      }
      match child.lookup_component(s.root) {
        Some(comp) =>
          // deliberately-broken fixtures are listed but never rendered
          // (their views trip parse issues on purpose).
          fields["s\{idx}"] = if s.renderable {
            warn_unresolved_args(s, child)
            comp.make(s.args)
          } else {
            Null
          }
        None => {
          // A blank pane and nothing said is the failure a hand-written story
          // list actually produces; say it.
          @tutuca.warn(
            "storybook: story '\{s.id}' names no component '\{s.root}' in module '\{s.module_.name}'",
          )
          fields["s\{idx}"] = Null
        }
      }
      idx = idx + 1
    }
  }
  let root_value = ShellInst::make(spec, fields).to_value()
  let app = @app.App::new(root_scope, root_value, root_node, opts)
  // The panel layer gets the app it has been holding a slot for. Before
  // `start()`, so a panel that wants to know about the first render can.
  (panels.attach)(app)
  app.start()
  // tutuca has no lifecycle: the host dispatches `init`, which the shell uses
  // to restore URL state and to fan `init` out to the panes that load data on
  // init (request-example, personal-site, …). Always sent so the URL restore
  // runs even when no story needs a data init.
  app.send_at_root("init") |> ignore
  app
}
