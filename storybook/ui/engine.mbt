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
/// Read a string field, defaulting to "" for any non-string (or missing) value.
fn str_field(inst : @component.Instance, name : String) -> String {
  match inst.get(name) {
    Str(s) => s
    _ => ""
  }
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
/// handler is about to make (`this` is still the pre-change instance).
fn snapshot(
  inst : @component.Instance,
  story? : String,
  focus? : String,
  filter? : String,
) -> @tutuca.Value {
  Map({
    "story": Str(story.unwrap_or(str_field(inst, "active"))),
    "focus": Str(focus.unwrap_or(str_field(inst, "focus"))),
    "filter": Str(filter.unwrap_or(str_field(inst, "filter"))),
  })
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
/// Recompute sidebar visibility from `filter`: each story's `vN` flag (nav row
/// shown) and each section's `gvK` flag (header shown when any of its rows
/// match). An empty filter shows everything. `filter_text`/`sec_of` are aligned
/// with the global story index N used for the `sN`/`vN` fields.
fn apply_filter(
  inst : @component.Instance,
  filter : String,
  filter_text : Array[String],
  sec_of : Array[Int],
  num_sections : Int,
) -> @component.Instance {
  let mut out = inst.set("filter", Str(filter))
  let active = filter != ""
  let sec_any = Array::make(num_sections, false)
  for i in 0..<filter_text.length() {
    let m = !active || fuzzy_match(filter, filter_text[i])
    out = out.set("v\{i}", Bool(m))
    if m {
      sec_any[sec_of[i]] = true
    }
  }
  for k in 0..<num_sections {
    out = out.set("gv\{k}", Bool(!active || sec_any[k]))
  }
  out
}

///|
/// Generate the gallery root component from the grouped sections. Field naming
/// (`sN`/`lN`/`vN`) follows the SAME nested iteration order `mount` uses, so
/// indices line up. `gvK` is per section index K.
pub fn shell_component(sections : Array[@sb.Section]) -> @component.Component {
  let fields : Map[String, @component.FieldSpec] = {
    "active": @component.FieldSpec::of_default(Str("")),
    "filter": @component.FieldSpec::of_default(Str("")),
    "focus": @component.FieldSpec::of_default(Str("")),
    "focusValue": @component.FieldSpec::of_default(Null),
    "sidebarCollapsed": @component.FieldSpec::of_default(Bool(false)),
  }
  // Metadata captured by the handler closures, aligned with the global story
  // index N: the id, the fuzzy-match haystack, and the owning section index.
  // `id_to_field` maps a renderable story's id to its `sN` field (for focus).
  let filter_text : Array[String] = []
  let sec_of : Array[Int] = []
  let id_to_field : Map[String, String] = {}
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
  sb.write_string("<div class=\"flex min-h-screen\" @hide=\"truthy? .focus\">")
  // collapsed rail: a single button to bring the sidebar back
  sb.write_string(
    "<button class=\"btn btn-ghost btn-sm self-start m-2\" title=\"Show sections\"" +
    " @show=\".sidebarCollapsed\" @on.click=\"$toggleSidebarCollapsed\">»</button>",
  )
  // sidebar
  sb.write_string(
    "<aside class=\"w-64 shrink-0 border-r border-base-300 p-3 overflow-y-auto\" @hide=\".sidebarCollapsed\">",
  )
  sb.write_string("<div class=\"flex items-center gap-2 mb-3\">")
  sb.write_string(
    "<button class=\"btn btn-ghost btn-sm\" title=\"Hide sections\" @on.click=\"$toggleSidebarCollapsed\">«</button>",
  )
  sb.write_string("<h1 class=\"text-lg font-bold flex-1\">Storybook</h1></div>")
  sb.write_string(
    "<input class=\"input input-sm w-full mb-3\" type=\"search\" placeholder=\"Filter\"" +
    " :value=\".filter\" @on.input=\"onFilter value\" @on.keydown+cancel=\"onClearFilter\" />",
  )
  let mut idx = 0
  let mut sec_index = 0
  for sec in sections {
    sb.write_string("<div class=\"mb-3\" @show=\".gv\{sec_index}\">")
    sb.write_string(
      "<div class=\"text-xs font-semibold uppercase opacity-50 mb-1\">\{esc(sec.title)}</div>",
    )
    for s in sec.stories {
      filter_text.push("\{s.title} \{s.section} \{s.description}")
      sec_of.push(sec_index)
      let id = esc_attr(s.id)
      sb.write_string(
        "<a id=\"nav-\{s.id}\" @show=\".v\{idx}\"" +
        " @if.class=\"equals? .active '\{id}'\"" +
        " @then=\"'block px-2 py-1 rounded text-sm cursor-pointer bg-primary text-primary-content'\"" +
        " @else=\"'block px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-200'\"" +
        " @on.click=\"onSelect '\{id}'\">\{esc(s.title)}</a>",
      )
      idx = idx + 1
    }
    sb.write_string("</div>")
    sec_index = sec_index + 1
  }
  sb.write_string("</aside>")
  // content panes
  sb.write_string("<main class=\"flex-1 p-4 overflow-y-auto\">")
  idx = 0
  for sec in sections {
    for s in sec.stories {
      fields["s\{idx}"] = @component.FieldSpec::of_default(Null)
      fields["l\{idx}"] = @component.FieldSpec::of_default(Str(""))
      fields["v\{idx}"] = @component.FieldSpec::of_default(Bool(true))
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
    fields["gv\{k}"] = @component.FieldSpec::of_default(Bool(true))
  }
  // Sidebar filter: recompute row/header visibility and persist the filter.
  let on_filter : @component.InstanceHandler = (inst, args, ctx) => {
    let value = match args {
      [Str(v), ..] => v
      _ => ""
    }
    ctx.request(
      "persistState",
      [snapshot(inst, filter=value), Bool(false)],
      @tutuca.RequestOpts::new(),
    )
    Some(apply_filter(inst, value, filter_text, sec_of, num_sections))
  }
  let input : Map[String, @component.InstanceHandler] = {
    "onFilter": on_filter,
    "onClearFilter": (inst, _args, ctx) => {
      ctx.request(
        "persistState",
        [snapshot(inst, filter=""), Bool(false)],
        @tutuca.RequestOpts::new(),
      )
      Some(apply_filter(inst, "", filter_text, sec_of, num_sections))
    },
    // Select a section pane; push a history entry so Back returns to the prior
    // story.
    "onSelect": (inst, args, ctx) => {
      let id = match args {
        [Str(v), ..] => v
        _ => ""
      }
      ctx.request(
        "persistState",
        [snapshot(inst, story=id), Bool(true)],
        @tutuca.RequestOpts::new(),
      )
      Some(inst.set("active", Str(id)))
    },
    "onFocusStory": (inst, args, ctx) => {
      let id = match args {
        [Str(v), ..] => v
        _ => ""
      }
      match id_to_field.get(id) {
        Some(fld) => {
          ctx.request(
            "persistState",
            [snapshot(inst, focus=id), Bool(true)],
            @tutuca.RequestOpts::new(),
          )
          Some(inst.set("focus", Str(id)).set("focusValue", inst.get(fld)))
        }
        None => Some(inst)
      }
    },
    "onFocusClose": (inst, _args, ctx) => {
      ctx.request(
        "persistState",
        [snapshot(inst, focus=""), Bool(false)],
        @tutuca.RequestOpts::new(),
      )
      Some(inst.set("focus", Str("")).set("focusValue", Null))
    },
  }
  // On init (and Back/Forward, when the host re-sends it) restore selection,
  // filter, and focus from the URL, then fan `init` out to the panes that load
  // data on init. loadState 404s harmlessly on hosts without URL persistence
  // (the error path in response.loadState keeps the defaults).
  let receive : Map[String, @component.InstanceHandler] = {
    "init": (inst, _args, ctx) => {
      ctx.request("loadState", [], @tutuca.RequestOpts::new())
      for f in init_fields {
        ctx.send_at_path(ctx.path().concat([@tutuca.FieldStep(f)]), "init", [])
      }
      Some(inst)
    },
  }
  let response : Map[String, @component.InstanceHandler] = {
    "loadState": (inst, args, _ctx) => {
      match args {
        // success: the host returns { story, focus, filter }
        [Map(state), ..] => {
          let story = str_of(state.get("story"))
          let focus = str_of(state.get("focus"))
          let filter = str_of(state.get("filter"))
          let mut out = inst
          // Any story id selects its pane (renderable panes and lint fixtures
          // alike); an id that matches nothing just leaves every pane hidden.
          if story != "" {
            out = out.set("active", Str(story))
          }
          out = apply_filter(out, filter, filter_text, sec_of, num_sections)
          match id_to_field.get(focus) {
            Some(fld) =>
              out = out.set("focus", Str(focus)).set("focusValue", inst.get(fld))
            None => ()
          }
          Some(out)
        }
        // error / no state: keep the defaults set by mount
        _ => Some(inst)
      }
    },
  }
  @component.component(
    name="Storybook",
    view=sb.to_string(),
    fields~,
    input~,
    receive~,
    response~,
  )
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
  url_handlers? : Map[String, @component.RequestFn] = {},
) -> @app.App[N] raise {
  let root_scope = @component.ComponentStack::new()
  let shell = shell_component(sections)
  root_scope.register_components([shell])
  if !url_handlers.is_empty() {
    root_scope.register_request_handlers(url_handlers)
  }
  let args : Map[String, @tutuca.Value] = {}
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      let child = root_scope.enter()
      child.register_components(s.module_.components)
      child.register_macros(s.module_.macros)
      child.register_request_handlers(s.module_.requests)
      if idx == 0 {
        args["active"] = Str(s.id)
      }
      match child.lookup_component(s.root) {
        Some(comp) => {
          // lint fixtures are linted but never rendered (their views trip
          // rules on purpose); build an instance only for renderable stories.
          args["s\{idx}"] = if s.renderable {
            comp.make(s.args).to_value()
          } else {
            Null
          }
          args["l\{idx}"] = Str(lint(comp))
        }
        None => {
          args["s\{idx}"] = Null
          args["l\{idx}"] = Str("(root component '\{s.root}' not found)")
        }
      }
      idx = idx + 1
    }
  }
  let root_value = shell.make(args).to_value()
  let app = @app.App::new(root_scope, root_value, root_node, opts)
  app.start()
  // tutuca has no lifecycle: the host dispatches `init`, which the shell uses
  // to restore URL state and to fan `init` out to the panes that load data on
  // init (request-example, personal-site, …). Always sent so the URL restore
  // runs even when no story needs a data init.
  app.send_at_root("init")
  app
}
