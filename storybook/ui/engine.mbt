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
/// The component behind a story's instance, or None.
///
/// The same resolution the Fuzz tab does before it draws a plan, and it has to
/// be a resolution rather than something remembered from `build_shell`: a
/// story's instance is REPLACED as it is driven, and the component behind it is
/// the stable thing.
fn ShellSpec::comp_of(
  self : ShellSpec,
  instance : @tutuca.Value,
) -> @component.Component? {
  guard self.comps is Some(cs) else { return None }
  cs.get_comp_for(instance)
}

///|
/// The Spec tab's content: the story component's `<script type="tutuca/spec">`
/// block, re-parsed and rendered as what it declares.
fn ShellSpec::spec_of(
  self : ShellSpec,
  instance : @tutuca.Value,
) -> @tutuca.Value {
  self.insp.spec_panel(comp?=self.comp_of(instance))
}

///|
/// The Raw tab's: the same block, verbatim.
fn ShellSpec::spec_source_of(
  self : ShellSpec,
  instance : @tutuca.Value,
) -> @tutuca.Value {
  self.insp.spec_source_panel(comp?=self.comp_of(instance))
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
    // Story | Instance for one pane. Switching TO the instance tab builds the
    // explorer (it is Null until then), which is also the only place it is
    // built from a cold start — `obj_with_field` only keeps a live one fresh.
    (Receive, "onStoryTab") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, tab) = match args {
            [Num(n), Str(t), ..] => (n.to_int(), t)
            _ => (-1, "story")
          }
          guard idx >= 0 else { return done(self) }
          let next = self.set("t\{idx}", Str(tab))
          done(
            match tab {
              "instance" =>
                next.set("i\{idx}", self.spec.explorer_of(self.get("s\{idx}")))
              // Built once and then left alone. A recording survives you
              // looking away from it, so unlike the explorer this is not
              // dropped on the way out — a panel that reset itself would lose
              // the session you just captured.
              "trace" => {
                let cur = next.get("r\{idx}")
                let with_panel = if cur is Null {
                  next.set("r\{idx}", self.spec.insp.trace_panel())
                } else {
                  next
                }
                with_panel.set("i\{idx}", Null)
              }
              // Same rule as the Trace panel, for the same reason: a run you
              // just watched break an invariant is not something to throw away
              // because you looked at the story again. The knobs come from the
              // shell's own `fz*` fields so an unopened tab still has a seed.
              "fuzz" => {
                let cur = next.get("f\{idx}")
                let with_panel = if cur is Null {
                  next.set(
                    "f\{idx}",
                    self.spec.insp.fuzz_panel(
                      seed=self.get("fzSeed").str(default="1"),
                      steps=self.get("fzSteps").str(default="40"),
                      source=self.get("fzSource").str(default="public"),
                    ),
                  )
                } else {
                  next
                }
                with_panel.set("i\{idx}", Null)
              }
              // A declaration cannot go stale — the component behind a story
              // is the one thing about it that never changes — so both spec
              // panels are built once and then left alone. Built lazily all
              // the same: a gallery has ~50 stories, and re-parsing every
              // block at mount to render none of them is pure cost.
              "spec" => {
                let cur = next.get("d\{idx}")
                let with_panel = if cur is Null {
                  next.set("d\{idx}", self.spec.spec_of(self.get("s\{idx}")))
                } else {
                  next
                }
                with_panel.set("i\{idx}", Null)
              }
              "raw" => {
                let cur = next.get("w\{idx}")
                let with_panel = if cur is Null {
                  next.set(
                    "w\{idx}",
                    self.spec.spec_source_of(self.get("s\{idx}")),
                  )
                } else {
                  next
                }
                with_panel.set("i\{idx}", Null)
              }
              // dropped on the way out: an explorer is a whole component tree,
              // and a closed tab has no use for one.
              _ => next.set("i\{idx}", Null)
            },
          )
        }),
      )
    // A click on the page, while selection mode is on.
    //
    // The shell raising an intent on the host's behalf. The CLICK is the
    // host's — a document listener is not something a component can install —
    // but only a component can raise an intent, so the glue sends this and the
    // shell forwards it. `pick_at` is what turns the node into the list.
    (Receive, "onTraceCandidates") =>
      Some(
        Handler((args, ctx) => {
          let list : @tutuca.Value = match args {
            [l, ..] => l
            _ => List([])
          }
          ctx.intent(
            "traceCandidates",
            [list],
            @tutuca.IntentOpts::new(route=[Lex]),
          )
          done(self)
        }),
      )
    // The host writing a rebuilt panel back in.
    //
    // The one direction that has to exist: recording is the host's — a
    // transactor is the one thing a component cannot reach — so the panel a
    // component shows is a value the host hands down, and this is the door it
    // comes through. Addressed at the root because the host knows the story
    // index and nothing else about where the pane lives.
    (Receive, "setTracePanel") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, panel) = match args {
            [Num(n), p, ..] => (n.to_int(), p)
            _ => (-1, (Null : @tutuca.Value))
          }
          guard idx >= 0 else { return done(self) }
          done(self.set("r\{idx}", panel))
        }),
      )
    // The same door, for the Fuzz pane. A run is the host's for the reason a
    // recording is: it drives the transactor and remounts the component, and a
    // component can do neither.
    (Receive, "setFuzzPanel") =>
      Some(
        Handler((args, _ctx) => {
          let (idx, panel) = match args {
            [Num(n), p, ..] => (n.to_int(), p)
            _ => (-1, (Null : @tutuca.Value))
          }
          guard idx >= 0 else { return done(self) }
          done(self.set("f\{idx}", panel))
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
    // The knobs, written back so the shell and the panel cannot disagree about
    // what seed the rows underneath were drawn at.
    (Receive, "setFuzzConfig") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(seed), Str(steps), Str(source), ..] =>
              done(
                self
                .set("fzSeed", Str(seed))
                .set("fzSteps", Str(steps))
                .set("fzSource", Str(source)),
              )
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
              done(self.set("focus", Str(id)).set("focusValue", self.get(fld)))
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
          done(self.set("focus", Str("")).set("focusValue", Null))
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
    // The Fuzz tab's knobs, on the shell rather than in the panel: the panel
    // is rebuilt by the host on every change, so a knob that lived only there
    // would be read back from the thing that is about to be replaced. They are
    // gallery-wide on purpose — a seed is what you carry from one story to the
    // next when you are looking for the same shape of bug.
    "fzSeed": Str("1"),
    "fzSteps": Str("40"),
    "fzSource": Str("public"),
  }
  // Metadata captured by the handlers, aligned with the global story index N:
  // the fuzzy-match haystack and the owning section index. `id_to_field` maps
  // a renderable story's id to its `sN` field (for focus).
  let filter_text : Array[String] = []
  let sec_of : Array[Int] = []
  let id_to_field : Map[String, String] = Map([])
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
    " :value=\".filter\" @on.input=\"onFilter e.value\" @on.keydown+cancel=\"onClearFilter\" />",
  )
  sb.write_string(
    "<select class=\"select select-sm w-auto\" title=\"Theme\" :value=\".theme\" @on.input=\"onSelectTheme e.value\">",
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
      // the per-story tab, and the explorer the Instance tab renders. `i<N>`
      // starts Null and is built the first time the tab is opened: a gallery
      // has ~50 stories and nobody is looking at 50 explorers.
      defaults["t\{idx}"] = Str("story")
      defaults["i\{idx}"] = Null
      defaults["r\{idx}"] = Null
      defaults["f\{idx}"] = Null
      // the Spec and Raw panels, built the first time their tab is opened
      defaults["d\{idx}"] = Null
      defaults["w\{idx}"] = Null
      if s.renderable {
        id_to_field[s.id] = "s\{idx}"
        if s.init {
          init_fields.push("s\{idx}")
        }
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
        // Story | Instance, per story. The Instance pane renders the
        // inspector's explorer over THIS story's live instance — `i<N>` is
        // rebuilt whenever `s<N>` is written (see obj_with_field), so it
        // tracks the story as you drive it.
        sb.write_string(
          "<div role=\"tablist\" class=\"tabs tabs-sm mb-2\">" +
          "<a role=\"tab\" class=\"tab story-tab\"" +
          " @if.class=\".t\{idx} is 'story'\"" +
          " @then=\"'tab tab-active story-tab'\" @else=\"'tab story-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'story'\">Story</a>" +
          "<a role=\"tab\" class=\"tab instance-tab\"" +
          " @if.class=\".t\{idx} is 'instance'\"" +
          " @then=\"'tab tab-active instance-tab'\" @else=\"'tab instance-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'instance'\">Instance</a>" +
          "<a role=\"tab\" class=\"tab trace-tab\"" +
          " @if.class=\".t\{idx} is 'trace'\"" +
          " @then=\"'tab tab-active trace-tab'\" @else=\"'tab trace-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'trace'\">Trace</a>" +
          "<a role=\"tab\" class=\"tab fuzz-tab\"" +
          " @if.class=\".t\{idx} is 'fuzz'\"" +
          " @then=\"'tab tab-active fuzz-tab'\" @else=\"'tab fuzz-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'fuzz'\">Fuzz</a>" +
          "<a role=\"tab\" class=\"tab spec-tab\"" +
          " @if.class=\".t\{idx} is 'spec'\"" +
          " @then=\"'tab tab-active spec-tab'\" @else=\"'tab spec-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'spec'\">Spec</a>" +
          "<a role=\"tab\" class=\"tab raw-tab\"" +
          " @if.class=\".t\{idx} is 'raw'\"" +
          " @then=\"'tab tab-active raw-tab'\" @else=\"'tab raw-tab'\"" +
          " @on.click=\"onStoryTab \{idx} 'raw'\">Raw</a>" +
          "</div>",
        )
        sb.write_string(
          "<div @show=\".t\{idx} is 'story'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
          "<x render=\".s\{idx}\"></x></div>",
        )
        sb.write_string(
          "<div @show=\".t\{idx} is 'instance'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".i\{idx}\"></x></div>",
        )
        // The Trace pane. `r<N>` is the panel — the recorder bar, and once
        // something has been recorded, the recording. Unlike `i<N>` it is NOT
        // dropped when the tab closes: a recording survives you looking away
        // from it, and a panel that reset itself would be a panel that loses
        // the session you just captured.
        sb.write_string(
          "<div @show=\".t\{idx} is 'trace'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".r\{idx}\"></x></div>",
        )
        // The Fuzz pane renders the STORY as well as the panel, and that is
        // the one thing about it that is not a copy of the Trace pane. A run
        // is watched: the whole reason to drive generated dispatches here
        // rather than under `moon test` is that the component is on screen
        // while they land, so a pane that replaced it with a list of what was
        // sent would be the headless run with extra steps.
        //
        // The same `s<N>` the Story tab renders, so it is one instance and not
        // a second mount — which is also what makes the panel's rows and the
        // picture agree.
        sb.write_string(
          "<div @show=\".t\{idx} is 'fuzz'\" class=\"flex flex-col gap-2\">" +
          "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100\">" +
          "<x render=\".s\{idx}\"></x></div>" +
          "<div class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".f\{idx}\"></x></div></div>",
        )
        // The two halves of one string, and the string is now load-bearing:
        // the Fuzz tab derives a component's generators and its whole oracle
        // from `Component::spec`, so what the block DECLARES stopped being
        // something you read the file for and became something the story has
        // to be able to show. Parsed on the left, verbatim on the right —
        // the parse is what the runtime reads, the source is what the author
        // edits, and a reader reconciling a surprising verdict wants both.
        sb.write_string(
          "<div @show=\".t\{idx} is 'spec'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".d\{idx}\"></x></div>",
        )
        sb.write_string(
          "<div @show=\".t\{idx} is 'raw'\"" +
          " class=\"border border-base-300 rounded-lg p-4 bg-base-100 overflow-auto\">" +
          "<x render=\".w\{idx}\"></x></div>",
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
/// Mount the gallery on `root_node`: register the shell (and any host URL
/// persistence handlers) in the root scope, each story's module in its own
/// child scope, pre-build each story instance from that scope, seed them as the
/// shell's `sN` fields, and start the app. `url_handlers` supplies the
/// `persistState`/`loadState` request handlers (the wasm host wires them to the
/// browser history/location; native/test hosts pass none and the gallery runs
/// without URL sync).
/// The gallery's own recording, and the story it is about.
///
/// Held by the HOST rather than in the shell's state, because that is where it
/// has to live: recording is installing a `Recorder` on a transactor, and a
/// transactor is the one thing a component cannot reach. The shell holds the
/// PANEL — a value handed down through `setTracePanel` — and this holds the
/// recording itself.
priv struct TraceSession {
  mut recorder : @trace.TraceRecorder?
  mut scoped : @trace.ScopedRecorder?
  mut taken : @trace.Trace?
  /// The story index the recording is about, so the panel goes back to the
  /// pane that started it.
  mut idx : Int
  mut scope : String
  mut selected_place : String?
  /// Whether a click on the page means "pick this" rather than "use this".
  mut selecting : Bool
  /// The candidates a click produced, or the recording's own places when
  /// nobody has clicked. Two lists of the same things offered for the same
  /// reason, so one field holds either.
  mut candidates : Array[(String, String)]?
}

///|
fn TraceSession::new() -> TraceSession {
  {
    recorder: None,
    scoped: None,
    taken: None,
    idx: -1,
    scope: "all",
    selected_place: None,
    selecting: false,
    candidates: None,
  }
}

///|
/// What the session has recorded so far, whichever strategy is installed.
fn TraceSession::current(self : TraceSession) -> @trace.Trace? {
  match (self.scoped, self.recorder) {
    (Some(r), _) => Some(r.take())
    (_, Some(r)) => Some(r.take())
    _ => self.taken
  }
}

///|
fn TraceSession::recording(self : TraceSession) -> Bool {
  self.recorder is Some(_) || self.scoped is Some(_)
}

///|
pub fn[N : @vdom.DomWalk] mount(
  sections : Array[@sb.Section],
  root_node : N,
  opts : @vdom.RenderOpts[N],
  url_handlers? : Map[String, Array[@component.IntentFn]] = Map([]),
  /// The Fuzz tab's two browser effects. Defaulted to nothing, so a headless
  /// mount gets the tab minus the frame loop and the profiler marks — the two
  /// things a terminal has no use for.
  fuzz_effects? : FuzzEffects = FuzzEffects::none(),
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
    root_scope.register_intent_handlers(url_handlers)
  }
  // The recorder's three intents, answered here because only the host has a
  // transactor to install one on. The app does not exist yet, so they close
  // over a slot that `App::new` fills a few lines down — the same shape
  // `spec.comps` uses for the same reason.
  let app_slot : Ref[@app.App[N]?] = { val: None, }
  let session = TraceSession::new()
  root_scope.register_intent_handlers(
    trace_handlers(app_slot, session, spec, sections),
  )
  // The Fuzz tab's, for the same reason and one more: shrinking remounts the
  // story dozens of times, which a component can do even less than it can
  // reach a transactor.
  let fuzz = FuzzSession::new()
  root_scope.register_intent_handlers(
    fuzz_handlers(app_slot, fuzz, spec, sections, fuzz_effects),
  )
  // What the page's animation frame lands on. A CLOSURE in a slot rather than
  // a generic function the host calls, because the host has no `N` to name:
  // `demo/storybook_wasm` knows it mounted on a `WasmNode` and should not have
  // to say so again to advance a run it did not start.
  fuzz_tick_slot.val = Some(() => {
    match app_slot.val {
      Some(app) => fuzz_advance(app, fuzz, spec, fuzz_effects)
      None => ()
    }
  })
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      let child = root_scope.enter()
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
  app_slot.val = Some(app)
  app.start()
  // tutuca has no lifecycle: the host dispatches `init`, which the shell uses
  // to restore URL state and to fan `init` out to the panes that load data on
  // init (request-example, personal-site, …). Always sent so the URL restore
  // runs even when no story needs a data init.
  app.send_at_root("init") |> ignore
  app
}

// ---------------------------------------------------------------------------
// recording the gallery
// ---------------------------------------------------------------------------

///|
/// The story the gallery is currently showing, as an index — or -1.
fn active_index(sections : Array[@sb.Section], active : String) -> Int {
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      if s.id == active {
        return idx
      }
      idx = idx + 1
    }
  }
  -1
}

///|
/// Where a story's instance lives in the shell's state.
///
/// The shell's field set is `sN` per story, so a story IS a place — which is
/// what makes "record only this example" expressible at all: it is a cut at
/// `.sN`, and the same operation that trims a finished recording.
fn story_place(idx : Int) -> @trace.Place {
  @trace.Place([{ field: "s\{idx}", key: None, }])
}

///|
/// Install a recorder, or say why not.
///
/// A scope of `all` records the gallery whole; `example` cuts to the story on
/// screen. `section` has no place of its own — a section is a sidebar grouping
/// and not a component — so it records whole and says so, which is honest in a
/// way that quietly recording something else would not be.
fn[N] start_recording(
  app : @app.App[N],
  session : TraceSession,
  idx : Int,
  scope : String,
) -> Unit {
  session.idx = idx
  session.scope = scope
  session.taken = None
  let root = app.root_value().to_component_json()
  if scope == "example" && idx >= 0 {
    let place = story_place(idx)
    let cut = @trace.cut_root(root, place).unwrap_or(Json::null())
    let r = @trace.ScopedRecorder::new(at=place, root=cut, origin={
      module_: "storybook",
      component: "",
      example: "",
      view: "",
      fingerprint: "",
    })
    session.scoped = Some(r)
    session.recorder = None
    app.transactor.set_recorder(r)
  } else {
    let r = @trace.TraceRecorder::new(root~, origin={
      module_: "storybook",
      component: "",
      example: "",
      view: "",
      fingerprint: "",
    })
    session.recorder = Some(r)
    session.scoped = None
    app.transactor.set_recorder(r)
  }
}

///|
/// Take the recording and put the recorder back.
///
/// Back to `NullRecorder` and not merely "stopped": the default records nothing
/// and costs nothing, and leaving a live recorder installed after somebody
/// pressed Stop would be the gallery quietly still recording.
fn[N] stop_recording(app : @app.App[N], session : TraceSession) -> Unit {
  session.taken = session.current()
  session.recorder = None
  session.scoped = None
  app.transactor.set_recorder(@transactor.NullRecorder::{ })
}

///|
/// Rebuild the panel and hand it to the pane that owns it.
///
/// Through `send_at_root` because that is the host's door into a running app,
/// and the shell routes it to `rN` — the host knows the story index and nothing
/// else about where the pane lives.
fn[N] push_panel(
  app : @app.App[N],
  session : TraceSession,
  spec : ShellSpec,
  tab? : String = "",
) -> Unit {
  guard session.idx >= 0 else { return }
  let t = session.current()
  let tab = if tab != "" {
    tab
  } else if t is Some(_) && !session.recording() {
    "trace"
  } else {
    "record"
  }
  let panel = spec.insp.trace_panel(
    trace?=t,
    tab~,
    recording=session.recording(),
    scope=session.scope,
    selecting=session.selecting,
    selected_place?=session.selected_place,
    // A click replaces the picker's list with what is under it. The same
    // component either way: "the places this recording touched" and "the
    // components under what you clicked" are the same list of the same things,
    // offered for the same reason.
    places?=match session.candidates {
      Some(cs) =>
        Some(
          spec.insp.place_candidates(
            candidates_for(session, cs),
            t.unwrap_or(@trace.Trace::new(root=Json::null())),
            selected?=session.selected_place,
          ),
        )
      None => None
    },
  )
  app.send_at_root("setTracePanel", args=[Num(session.idx.to_double()), panel])
  |> ignore
}

///|
/// Whether a click on the page means "pick this" rather than "use this".
///
/// A module-level flag, and the reason is that a gallery mounts ONCE per page:
/// the shell is the whole page, so there is one of these to be in. A host has
/// to ask before it dispatches a click — the answer decides whether the click
/// drives the app or points at it — and the alternative was threading a handle
/// out of `mount` into the one export a wasm host is allowed.
let selecting_now : Ref[Bool] = { val: false, }

///|
/// Whether the gallery is waiting to be pointed at.
///
/// Asked by a host's DOM listener before it dispatches: while this is true a
/// click is a pick, and letting it also reach the app would drive the app with
/// the click that was meant to point at it.
pub fn trace_selecting() -> Bool {
  selecting_now.val
}

///|
/// A clicked node turned into relocation candidates.
///
/// The one piece of selection mode a host cannot do without: a person can point
/// at a row far more easily than they can spell `.s3.rows[1]`, and the renderer
/// already stamped everything needed to read the ancestry back out of the DOM.
///
/// Public because the CLICK is the host's — a document listener is not
/// something a component can install, and the browser glue is where one lives.
/// This is what such a listener calls with the node it got.
///
/// The addresses are relative to the story when the recording was scoped to
/// one, because that is what the recording's own addresses are relative to:
/// offering a candidate a recording cannot be cut to would be offering an
/// empty trace.
pub fn[N : @vdom.DomWalk] pick_at(
  app : @app.App[N],
  node : N,
  root_node : N,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let root = app.root_value()
  for c in @render.components_at(node, root_node, app.scope.comps) {
    let place = @trace.Place::of_path(c.path.to_transaction_path())
    // The component's NAME, from the instance the address resolves to. Not
    // from the crossing's `cid`, which is a process-global counter and means
    // nothing outside this run.
    let name = match place.to_path().lookup(root) {
      Some(v) =>
        match v.schema() {
          Some(sc) => sc.name
          None => ""
        }
      None => ""
    }
    out.push((place.label(), name))
  }
  out
}

///|
/// The same, cut to the story a scoped recording is about.
///
/// A recording scoped to one story has story-relative addresses, so a candidate
/// has to be one too — and a click outside that story yields nothing, which is
/// the honest answer rather than an address the recording cannot use.
fn candidates_for(
  session : TraceSession,
  crossings : Array[(String, String)],
) -> Array[(String, String)] {
  guard session.scope == "example" && session.idx >= 0 else { return crossings }
  let prefix = "s\{session.idx}"
  let out : Array[(String, String)] = []
  for c in crossings {
    let (label, name) = c
    if label == prefix {
      out.push(("", name))
    } else if label.has_prefix(prefix + ".") {
      out.push((label[prefix.length() + 1:].to_owned(), name))
    }
  }
  out
}

///|
/// A click on the page, while selection mode is on.
///
/// The host's whole half of pointing at a component: it hands the node its
/// listener got, this reads the ancestry back out of the renderer's own DOM
/// markers and sends it in, and the panel comes back offering each one as
/// somewhere to cut the recording to.
///
/// Answers whether the click was consumed, so a caller knows whether to let it
/// through — a pick and a use are two different meanings for one click, and
/// doing both is doing the wrong one.
pub fn[N : @vdom.DomWalk] take_select_click(
  app : @app.App[N],
  node : N,
  root_node : N,
) -> Bool {
  if !selecting_now.val {
    return false
  }
  let found = pick_at(app, node, root_node)
  app.send_at_root("onTraceCandidates", args=[
    List(
      found.map(c => {
        (Map({ "place": Str(c.0), "component": Str(c.1) }) : @tutuca.Value)
      }),
    ),
  ])
  |> ignore
  true
}

///|
/// The three intents the recorder bar raises, answered by the host.
fn[N] trace_handlers(
  app_slot : Ref[@app.App[N]?],
  session : TraceSession,
  spec : ShellSpec,
  sections : Array[@sb.Section],
) -> Map[String, Array[@component.IntentFn]] {
  fn with_app(f : (@app.App[N]) -> Unit) -> Unit {
    match app_slot.val {
      Some(app) => f(app)
      None => ()
    }
  }

  {
    "traceStart": [
      @component.IntentFn((call, answer) => {
        let scope = match call.args {
          [Str(s), ..] => s
          _ => "all"
        }
        with_app(app => {
          let active = app.root_value().field("active").str(default="")
          let idx = active_index(sections, active)
          start_recording(app, session, idx, scope)
          push_panel(app, session, spec, tab="record")
        })
        answer(Ok(Str(scope)))
      }),
    ],
    "traceStop": [
      @component.IntentFn((_call, answer) => {
        with_app(app => {
          stop_recording(app, session)
          push_panel(app, session, spec)
        })
        answer(Ok(Null))
      }),
    ],
    "traceDiscard": [
      @component.IntentFn((_call, answer) => {
        session.taken = None
        session.selected_place = None
        session.selecting = false
        selecting_now.val = false
        session.candidates = None
        with_app(app => push_panel(app, session, spec, tab="record"))
        answer(Ok(Null))
      }),
    ],
    // Selection mode on and off. Turning it OFF puts the recording's own
    // places back, because a stale list of candidates from a click nobody
    // remembers making is worse than no list.
    "traceSelect": [
      @component.IntentFn((_call, answer) => {
        session.selecting = !session.selecting
        selecting_now.val = session.selecting
        if !session.selecting {
          session.candidates = None
        }
        with_app(app => push_panel(app, session, spec, tab="trace"))
        answer(Ok(Bool(session.selecting)))
      }),
    ],
    // What a click on the page found. Raised by the shell on the host's
    // behalf, because the CLICK is the host's — a document listener is not
    // something a component can install — and the host is the only thing that
    // can rebuild the panel around the answer.
    "traceCandidates": [
      @component.IntentFn((call, answer) => {
        let cs : Array[(String, String)] = []
        match call.args {
          [List(items), ..] =>
            for it in items {
              cs.push(
                (
                  it.field("place").str(default=""),
                  it.field("component").str(default=""),
                ),
              )
            }
          _ => ()
        }
        session.candidates = Some(cs)
        session.selecting = false
        selecting_now.val = false
        with_app(app => push_panel(app, session, spec, tab="trace"))
        answer(Ok(Num(cs.length().to_double())))
      }),
    ],
    // Which candidate the reader chose. Kept rather than acted on: cutting the
    // recording is a separate press, and choosing a place is the thing a person
    // does several times before they mean it.
    "tracePick": [
      @component.IntentFn((call, answer) => {
        session.selected_place = match call.args {
          [Str(p), ..] => Some(p)
          _ => None
        }
        with_app(app => push_panel(app, session, spec, tab="trace"))
        answer(Ok(Str(session.selected_place.unwrap_or(""))))
      }),
    ],
  }
}

// ---------------------------------------------------------------------------
// fuzzing the story on screen
// ---------------------------------------------------------------------------

///|
/// A property run over one story, and the story it is about.
///
/// Held by the HOST for the same reason `TraceSession` is, and one more.
/// Driving a generated script means pushing at the transactor, which a
/// component cannot reach; shrinking means remounting the component many
/// times, which a component can do even less. The shell holds the PANEL — a
/// value handed down through `setFuzzPanel` — and this holds the run.
///
/// The whole run is redrawn from `seed` rather than kept as a cursor into a
/// stored generator, which is what lets Reset be exact and what makes the
/// four knobs the run's entire address.
priv struct FuzzSession {
  mut plan : @fuzz.Plan?
  /// The story index the run is about, so the panel goes back to the pane that
  /// started it.
  mut idx : Int
  mut seed : UInt64
  mut steps : Int
  mut source : String
  /// The script as drawn. Redrawn whenever a knob moves, because a row list
  /// that outlived its seed would be a lie about what is going to be sent.
  mut script : Array[@fuzz.Action]
  /// What has run so far, and how far in.
  mut ran : Array[@fuzz.Step]
  mut at : Int
  /// What the next tick should do. `""` is idle.
  ///
  /// Every mode runs on the TICK and none of them runs inside the click that
  /// asked for it, and that is not a scheduling preference — it is what makes
  /// a run able to see its own refusals. A refusal is HELD for the duration of
  /// a dispatch and only the first one escapes ("one dispatch, one record,
  /// however many layers it walked" — `core/refusal.mbt`), so a run driven
  /// from inside a component's own dispatch chain is a run whose refusals are
  /// all deduplicated into the click that started it. Arming and stepping have
  /// to be two different turns.
  mut mode : String
  /// A Play is in flight: one dispatch per animation frame.
  mut playing : Bool
  mut outcome : @fuzz.Outcome?
  /// The shrunk reproducer, once somebody asked for one.
  mut reproducer : Array[@fuzz.Action]
}

///|
fn FuzzSession::new() -> FuzzSession {
  {
    plan: None,
    idx: -1,
    seed: 1,
    steps: 40,
    source: "public",
    mode: "",
    script: [],
    ran: [],
    at: -1,
    playing: false,
    outcome: None,
    reproducer: [],
  }
}

///|
/// The generator source a button names.
fn fuzz_source_of(name : String) -> @fuzz.Source {
  match name {
    "messages" => Declared(BEither)
    "properties" => Properties
    "internal" => InternalMutators
    _ => Public(BEither)
  }
}

///|
/// Everything about a run except the component: forget the steps, keep the
/// knobs.
fn FuzzSession::rearm(self : FuzzSession) -> Unit {
  self.ran = []
  self.at = -1
  self.outcome = None
  self.reproducer = []
  self.script = match self.plan {
    // A component with a `where` draws its dispatches AS IT GOES, against the
    // state each step lands in — an index cannot be drawn in range before the
    // list it indexes has a length. So there is no script to sample up front,
    // and `script` fills in one entry per step instead.
    Some(p) if p.state_aware() => []
    Some(p) => p.script(seed=self.seed, steps=self.steps)
    None => []
  }
}

///|
/// Rebuild the Fuzz panel and hand it down to the pane that owns it.
///
/// The mirror of `push_panel`, and the same shape for the same reason: the
/// host holds the run, so the host is the only thing that can say what the
/// panel shows.
fn[N] push_fuzz_panel(
  app : @app.App[N],
  session : FuzzSession,
  spec : ShellSpec,
) -> Unit {
  guard session.idx >= 0 else { return }
  let panel = spec.insp.fuzz_panel(
    seed=session.seed.to_string(),
    steps=session.steps.to_string(),
    source=session.source,
    run_steps=session.ran,
    at=session.at,
    planned=session.script.length(),
    playing=session.playing,
    can_run=session.plan is Some(_),
    no_plan_hint=if session.plan is Some(_) {
      ""
    } else {
      "This story's component declares no <script type=\"tutuca/spec\"> block, so there is nothing to derive generators from."
    },
    outcome?=session.outcome,
    unchecked=match session.plan {
      Some(p) => p.unchecked()
      None => []
    },
    reproducer=session.reproducer,
  )
  app.send_at_root("setFuzzPanel", args=[Num(session.idx.to_double()), panel])
  |> ignore
}

///|
/// Point the session at the story on screen, drawing its plan from the
/// component's own spec block.
///
/// Re-derived on every press rather than cached against the index: a story's
/// instance is replaced as it is driven, and the component behind it is the
/// stable thing — so the plan is cheap to rebuild and impossible to have stale.
fn[N] aim_fuzz(
  app : @app.App[N],
  session : FuzzSession,
  sections : Array[@sb.Section],
) -> Unit {
  let active = app.root_value().field("active").str(default="")
  let idx = active_index(sections, active)
  session.idx = idx
  session.plan = None
  guard idx >= 0 else { return }
  // The component behind the story's instance, resolved through the registry
  // the gallery already shares.
  let inst = app.root_value().field("s\{idx}")
  guard app.scope.comps.get_comp_for(inst) is Some(comp) else { return }
  session.plan = @fuzz.Plan::of_component(
    comp,
    source=fuzz_source_of(session.source),
  )
}

///|
/// One dispatch, at the story's own place.
///
/// Returns false when there is nothing left to send — which is what stops a
/// Play rather than a counter kept somewhere else.
fn[N] fuzz_step_once(app : @app.App[N], session : FuzzSession) -> Bool {
  guard session.plan is Some(plan) else { return false }
  let next = session.at + 1
  // How many steps are LEFT differs between the two draws: a sampled script
  // knows its own length, and a live one is bounded by the knob instead.
  let planned = if plan.state_aware() {
    session.steps
  } else {
    session.script.length()
  }
  guard next < planned else { return false }
  // A story lives at `.sN`, so a dispatch is addressed there and not at the
  // root — the same addressing the scoped recorder cuts at.
  let at = @tutuca.DispatchPath::of_steps(story_place(session.idx).to_steps())
  let h = @harness.Harness::over(app, app.root_node)
  // WHERE to read the state back from. The gallery is one app with every story
  // mounted under it, so the ROOT value is the shell — asking `neverEmpty` of
  // that would ask it of a thing with no `values` and get a confident answer
  // about the wrong component. `.sN` is the instance the rules are about, and
  // it is the same field the Story tab renders.
  let read = story_reader(app, session.idx)
  // Drawn now, from the state the last step left, and RECORDED — a reproducer
  // and the shrinker both work on the dispatches that were actually sent,
  // because replaying a shortened script would redraw different arguments.
  if plan.state_aware() {
    let now = @fuzz.settled(h, read~)
    guard plan.next_at(now, seed=session.seed, step=next) is Some(d) else {
      return false
    }
    session.script.push(d)
  }
  let step = plan.step(h, session.script[next], at~, read~) catch {
    _ => return false
  }
  session.ran.push(step)
  session.at = next
  if step.broke.length() > 0 {
    let rule = step.broke[0]
    session.outcome = Some(
      Broke(rule~, sentence=plan.sentence_of(rule), at=next),
    )
    return false
  }
  if step.disagreed.length() > 0 {
    session.outcome = Some(Disagreed(rule=step.disagreed[0], at=next))
    return false
  }
  if next == planned - 1 {
    session.outcome = Some(Held)
    return false
  }
  true
}

///|
/// The two browser effects a run needs, supplied by the host.
///
/// `storybook/ui` never touches the JS FFI — the same split the URL handlers
/// follow, and for the same reason: this package is checked and tested on
/// every backend, and a `globalThis` in it would make that untrue. The host
/// wires these to the page; a headless mount gets the defaults and the tab
/// still works, minus the two things a terminal has no use for.
pub(all) struct FuzzEffects {
  /// Ask the page to call the run's tick export on the next animation frame.
  ///
  /// A call OUT rather than a callback in, because a closure cannot cross into
  /// JS on wasm-gc — which is why every other browser effect in the gallery
  /// has this shape. One shot: the host arms the next frame only while a run
  /// is live, so there is no permanent frame loop.
  arm_frame : () -> Unit
  /// Bracket a step for the profiler, `(name, "start" | "end")`.
  ///
  /// It writes to DevTools' own Timings track rather than collecting a number
  /// here: the measurement is the browser's, and what a run owes it is a
  /// label. No fallback clock, on purpose — a second timebase nobody asked for
  /// is worse than none.
  mark : (String, String) -> Unit
}

///|
/// Effects that do nothing, for a mount with no page under it.
pub fn FuzzEffects::none() -> FuzzEffects {
  { arm_frame: () => (), mark: (_name, _phase) => (), }
}

///|
/// One step, marked for the profiler.
fn[N] fuzz_step_marked(
  app : @app.App[N],
  session : FuzzSession,
  fx : FuzzEffects,
) -> Bool {
  let next = session.at + 1
  let name = if next < session.script.length() {
    match session.script[next] {
      Message(Receive(n, _)) | Message(Intent(n, _)) => n
      SetProperty(n, _) => n
      InternalMutator(Receive(n, _)) | InternalMutator(Intent(n, _)) => n
    }
  } else {
    ""
  }
  if name != "" {
    (fx.mark)(name, "start")
  }
  let more = fuzz_step_once(app, session)
  if name != "" {
    (fx.mark)(name, "end")
  }
  more
}

///|
/// The Fuzz tab's intents, answered here because only the host has a
/// transactor to push at and a scope to remount from.
fn[N] fuzz_handlers(
  app_slot : Ref[@app.App[N]?],
  session : FuzzSession,
  spec : ShellSpec,
  sections : Array[@sb.Section],
  fx : FuzzEffects,
) -> Map[String, Array[@component.IntentFn]] {
  fn with_app(f : (@app.App[N]) -> Unit) -> Unit {
    match app_slot.val {
      Some(app) => f(app)
      None => ()
    }
  }

  {
    // A knob moved. Every one of them invalidates the drawn script, so all
    // three arrive together and the script is redrawn whole — a seed that no
    // longer describes the rows under it is the one state this must not have.
    "fuzzConfig": [
      @component.IntentFn((call, answer) => {
        match call.args {
          [Str(seed), Str(steps), Str(source), ..] => {
            session.seed = @string.parse_uint64(seed) catch {
              _ => session.seed
            }
            session.steps = @string.parse_int(steps) catch {
              _ => session.steps
            }
            session.source = source
          }
          _ => ()
        }
        with_app(app => {
          app.send_at_root("setFuzzConfig", args=[
            Str(session.seed.to_string()),
            Str(session.steps.to_string()),
            Str(session.source),
          ])
          |> ignore
          aim_fuzz(app, session, sections)
          session.rearm()
          push_fuzz_panel(app, session, spec)
        })
        answer(Ok(Str(session.source)))
      }),
    ],
    // The three run buttons ARM a mode and nothing more. The work happens on
    // the next tick, outside this dispatch — see `FuzzSession::mode` for why
    // that is a correctness requirement and not a scheduling choice.
    "fuzzStep": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, session, spec, fx, "step", sections))
        answer(Ok(Str("step")))
      }),
    ],
    // The whole script with no yield. What a flame chart wants: settle,
    // render and morph back to back, with no scheduler noise between them.
    "fuzzBurst": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, session, spec, fx, "burst", sections))
        answer(Ok(Str("burst")))
      }),
    ],
    // One dispatch per frame, until the script runs out or something breaks.
    // What a person wants, and what makes a DevTools recording show real
    // layout and paint rather than one blocking call.
    "fuzzPlay": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, session, spec, fx, "play", sections))
        answer(Ok(Bool(true)))
      }),
    ],
    "fuzzStop": [
      @component.IntentFn((_call, answer) => {
        session.playing = false
        session.mode = ""
        with_app(app => push_fuzz_panel(app, session, spec))
        answer(Ok(Bool(false)))
      }),
    ],
    // Back to the story's initial state, script and all. Remounting is what
    // makes it exact: rewinding a component by sending it the reverse of what
    // it received is not a thing that exists.
    "fuzzReset": [
      @component.IntentFn((_call, answer) => {
        session.playing = false
        with_app(app => {
          remount_story(app, session.idx, sections)
          aim_fuzz(app, session, sections)
          session.rearm()
          push_fuzz_panel(app, session, spec)
        })
        answer(Ok(Null))
      }),
    ],
    // The shortest script that still does it.
    //
    // Every candidate runs from a FRESH story, which is why this is the host's
    // and why it ends by putting the story back: shrinking drives the
    // component dozens of times, and what is on screen afterwards must be the
    // reproducer's own result rather than wherever the last candidate landed.
    "fuzzShrink": [
      @component.IntentFn((_call, answer) => {
        with_app(app => {
          guard session.plan is Some(plan) else { return }
          let idx = session.idx
          let failing = match session.outcome {
            Some(Broke(at~, ..)) | Some(Disagreed(at~, ..)) =>
              session.script[:at + 1].to_owned()
            _ => session.script
          }
          let at = @tutuca.DispatchPath::of_steps(story_place(idx).to_steps())
          // Always `Some`: the story is already mounted and this only puts
          // its value back, so unlike a remount that builds a fresh app from a
          // module, there is nothing here that can fail.
          let remount = () => {
            remount_story(app, idx, sections)
            Some(@harness.Harness::over(app, app.root_node))
          }
          session.reproducer = @fuzz.shrink(
            plan,
            failing,
            remount,
            at~,
            read=story_reader(app, idx),
          )
          // Leave the story showing what the reproducer does, not what the
          // last discarded candidate did.
          remount_story(app, idx, sections)
          session.ran = []
          session.at = -1
          session.outcome = None
          session.script = session.reproducer
          while fuzz_step_once(app, session) {

          }
          push_fuzz_panel(app, session, spec)
        })
        answer(Ok(Num(session.reproducer.length().to_double())))
      }),
    ],
  }
}

///|
/// Put a story back the way it was mounted.
///
/// The gallery builds `sN` from the component and the story's args at mount;
/// this is that line again, which is what makes a reset exact rather than
/// approximately undone.
fn[N] remount_story(
  app : @app.App[N],
  idx : Int,
  sections : Array[@sb.Section],
) -> Unit {
  guard idx >= 0 else { return }
  let mut i = 0
  for sec in sections {
    for s in sec.stories {
      if i == idx {
        // Through the REGISTRY and not the root scope: a story's components
        // are registered in a child scope of their own, so same-named
        // components across examples do not collide — and `lookup_component`
        // at the root would find none of them. The registry is shared by id
        // across every child scope, which is what makes this resolvable at
        // all, and it is the same route the Instance tab's explorer takes.
        guard s.renderable &&
          app.scope.comps.get_comp_for(app.root_value().field("s\{idx}"))
          is Some(comp) else {
          return
        }
        app.send_at_root("setStoryValue", args=[
          Num(idx.to_double()),
          comp.make(s.args),
        ])
        |> ignore
        return
      }
      i = i + 1
    }
  }
}

///|
/// The running gallery's frame handler, or none when nothing is mounted.
///
/// Package-level because there is one gallery per page — the same reason
/// `demo/storybook_wasm` keeps its app in a `Ref` for `on_popstate`.
let fuzz_tick_slot : Ref[(() -> Unit)?] = { val: None, }

///|
/// Point the session at the story, draw a fresh script, and ask for a frame.
///
/// The whole of what a run button does. Nothing is dispatched here — see
/// `FuzzSession::mode`.
fn[N] arm_run(
  app : @app.App[N],
  session : FuzzSession,
  spec : ShellSpec,
  fx : FuzzEffects,
  mode : String,
  sections : Array[@sb.Section],
) -> Unit {
  // Step continues a run in progress; Play and Burst start one. That is the
  // difference between the three and the only place it lives.
  //
  // A FINISHED run is not one in progress, so Step at the end of a script
  // starts a fresh one rather than doing nothing — which is what it did before
  // this clause, and what a dead button looks like.
  let finished = session.at >= session.script.length() - 1
  if mode != "step" ||
    finished ||
    session.plan is None ||
    session.script.is_empty() {
    aim_fuzz(app, session, sections)
    session.rearm()
  }
  session.mode = mode
  session.playing = mode == "play"
  push_fuzz_panel(app, session, spec)
  (fx.arm_frame)()
}

///|
/// Do what the armed mode says, then arm the next frame if there is more.
///
/// Called from the page's animation frame, and — crucially — from OUTSIDE any
/// dispatch. That is what lets each step be its own dispatch chain, so a
/// refusal it provokes is a refusal it can see.
///
/// Safe to call at any time: nothing armed, or nothing left to send, and it
/// stops. A page that arms one frame too many gets a no-op rather than a wrong
/// answer.
fn[N] fuzz_advance(
  app : @app.App[N],
  session : FuzzSession,
  spec : ShellSpec,
  fx : FuzzEffects,
) -> Unit {
  guard session.mode != "" else { return }
  let mode = session.mode
  match mode {
    // The whole script in one frame: settle, render and morph back to back,
    // which is the shape a flame chart is worth reading.
    "burst" => {
      (fx.mark)("burst", "start")
      while fuzz_step_marked(app, session, fx) {

      }
      (fx.mark)("burst", "end")
      session.mode = ""
    }
    _ => {
      let more = fuzz_step_marked(app, session, fx)
      if mode == "play" && more {
        // stays armed
      } else {
        session.playing = false
        session.mode = ""
      }
    }
  }
  // The panel every frame, because watching a run IS the point: the rows and
  // the component on screen have to move together, and a panel refreshed only
  // at the end would make Play look exactly like Burst.
  push_fuzz_panel(app, session, spec)
  if session.mode != "" {
    (fx.arm_frame)()
  }
}

///|
/// The page's animation-frame entry point.
///
/// Public and argument-free: it is called from JS through a wasm export, and
/// an export cannot be generic or take a node.
pub fn fuzz_tick() -> Unit {
  match fuzz_tick_slot.val {
    Some(f) => f()
    None => ()
  }
}

///|
/// The story's own instance, re-read on demand.
///
/// A closure rather than the value, because a run reads it back after every
/// step and the whole point is that it changed.
fn[N] story_reader(app : @app.App[N], idx : Int) -> @fuzz.Reader {
  @fuzz.Reader(() => app.root_value().field("s\{idx}"))
}
