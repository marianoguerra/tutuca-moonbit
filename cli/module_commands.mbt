// Module-command engines over a programmatically-provided ModuleDef (the
// MoonBit module-input answer: a native binary cannot import() user code, so
// user projects embed the CLI — build a main that calls
// plan_with_module(argv, your_module)). Each command honors the resolved
// output format: the cli/md text renderings (per-command default) plus a
// structured `json` for every command (the `--json` slice of the JS formatter
// matrix; `html` stays render-only, where the render command already emits it).

///|
priv struct ModArgs {
  name : String? // first bare positional: component-name filter
  limit : Int?
  title : String?
  view : String?
}

///|
fn parse_mod_args(args : Array[String]) -> ModArgs {
  let mut name : String? = None
  let mut limit : Int? = None
  let mut title : String? = None
  let mut view : String? = None
  let mut i = 0
  fn flag_value(arg : String, key : String) -> String? {
    let prefix = "--" + key + "="
    if arg.has_prefix(prefix) {
      return Some(arg[prefix.length():].to_owned())
    }
    None
  }

  while i < args.length() {
    let a = args[i]
    if a == "--limit" || a == "--title" || a == "--view" {
      let v = args.get(i + 1).unwrap_or("")
      match a {
        "--limit" => limit = Some(@strconv.from_str(v) catch { _ => 0 })
        "--title" => title = Some(v)
        _ => view = Some(v)
      }
      i += 2
      continue
    }
    match flag_value(a, "limit") {
      Some(v) => limit = Some(@strconv.from_str(v) catch { _ => 0 })
      None =>
        match flag_value(a, "title") {
          Some(v) => title = Some(v)
          None =>
            match flag_value(a, "view") {
              Some(v) => view = Some(v)
              None => if !a.has_prefix("-") && name is None { name = Some(a) }
            }
        }
    }
    i += 1
  }
  { name, limit, title, view }
}

///|
fn[T] capped(items : Array[T], limit : Int?) -> (Array[T], Bool) {
  match limit {
    Some(n) if n > 0 && n < items.length() => (items[0:n].to_owned(), true)
    _ => (items, false)
  }
}

///|
fn kind_name(k : @component.FieldKind) -> String {
  match k {
    FBool => "bool"
    FText => "text"
    FInt => "int"
    FFloat => "float"
    FList => "list"
    FMap => "map"
    FAny => "any"
    FComp(comp~, ..) => "comp(\{comp})"
    FSet => "set"
    FOMap => "omap"
  }
}

///|
fn ok(out : String) -> Emit {
  { out, err: "", exit_code: 0 }
}

///|
/// Emit a JSON value as the one-line-per-command result (pretty-printed like
/// agent-context). The `--json` slice of the JS formatter matrix.
fn json_ok(j : Json) -> Emit {
  ok(j.stringify(indent=2, escape_slash=false) + "\n")
}

///|
fn is_json(fmt : String) -> Bool {
  fmt == "json"
}

///|
fn module_error(opts : GlobalOpts, message : String) -> Emit {
  error_emit(opts, err(CODE_MODULE_SHAPE_MISMATCH, message))
}

///|
fn run_get(m : @component.ModuleDef, fmt : String) -> Emit {
  let names = m.components.map(c => c.name)
  if is_json(fmt) {
    return json_ok(
      Json::object({
        "module": m.name.to_json(),
        "components": names.to_json(),
        "counts": Json::object({
          "components": names.length().to_json(),
          "examples": m.examples.length().to_json(),
        }),
      }),
    )
  }
  ok(
    "module \{m.name}\n" +
    "components: \{names.length()} (\{names.join(", ")})\n" +
    "examples: \{m.examples.length()}\n",
  )
}

///|
fn run_list(m : @component.ModuleDef, args : ModArgs, fmt : String) -> Emit {
  let (names, truncated) = capped(m.components.map(c => c.name), args.limit)
  if is_json(fmt) {
    return json_ok(
      Json::object({
        "components": names.to_json(),
        "truncated": truncated.to_json(),
      }),
    )
  }
  let sb = StringBuilder()
  for n in names {
    sb <+ "\{n}\n"
  }
  if truncated {
    sb <+ "… truncated\n"
  }
  ok(sb.to_string())
}

///|
fn run_examples(m : @component.ModuleDef, args : ModArgs, fmt : String) -> Emit {
  let all = m.examples.filter(e => {
    match args.name {
      Some(n) => e.component == n
      None => true
    }
  })
  let (items, truncated) = capped(all, args.limit)
  if is_json(fmt) {
    return json_ok(
      Json::object({
        "examples": Json::array(
          items.map(e => {
            Json::object({
              "component": e.component.to_json(),
              "title": e.title.to_json(),
            })
          }),
        ),
        "truncated": truncated.to_json(),
      }),
    )
  }
  let sb = StringBuilder()
  for e in items {
    sb <+ "\{e.component} — \{e.title}\n"
  }
  if truncated {
    sb <+ "… truncated\n"
  }
  ok(sb.to_string())
}

///|
fn show_component_json(comp : @component.Component) -> Json {
  let fields : Map[String, Json] = {}
  for fname, spec in comp.fields {
    fields[fname] = Json::object({
      "kind": kind_name(spec.kind).to_json(),
      "default": spec.default.to_display_string().to_json(),
    })
  }
  let views : Array[String] = []
  for vname, _v in comp.views {
    views.push(vname)
  }
  let provide : Map[String, Json] = {}
  for pname, p in comp.provide {
    provide[pname] = p.val.to_string().to_json()
  }
  let lookup : Map[String, Json] = {}
  for lname, lk in comp.lookup {
    lookup[lname] = "\{lk.comp_name}.\{lk.provide_name}".to_json()
  }
  let handlers : Array[String] = []
  for hname, _h in comp.receive {
    handlers.push("receive:\{hname}")
  }
  for hname, _h in comp.input {
    handlers.push("input:\{hname}")
  }
  for hname, _h in comp.bubble {
    handlers.push("bubble:\{hname}")
  }
  for hname, _h in comp.response {
    handlers.push("response:\{hname}")
  }
  Json::object({
    "name": comp.name.to_json(),
    "fields": Json::object(fields),
    "views": views.to_json(),
    "provide": Json::object(provide),
    "lookup": Json::object(lookup),
    "handlers": handlers.to_json(),
  })
}

///|
fn run_show(
  m : @component.ModuleDef,
  args : ModArgs,
  fmt : String,
) -> Emit raise {
  let _scope = m.build_scope() // compiles provide/lookup for display
  fn selected(comp : @component.Component) -> Bool {
    args.name is None || args.name == Some(comp.name)
  }

  if is_json(fmt) {
    let comps : Array[Json] = []
    for comp in m.components {
      if selected(comp) {
        comps.push(show_component_json(comp))
      }
    }
    return json_ok(Json::object({ "components": Json::array(comps) }))
  }
  let sb = StringBuilder()
  for comp in m.components {
    if args.name is Some(n) && comp.name != n {
      continue
    }
    sb <+ "# \{comp.name}\n"
    if !comp.fields.is_empty() {
      sb <+ "fields:\n"
      for fname, spec in comp.fields {
        sb <+
          "  \{fname}: \{kind_name(spec.kind)} = \{spec.default.to_display_string()}\n"
      }
    }
    let views : Array[String] = []
    for vname, _v in comp.views {
      views.push(vname)
    }
    sb <+ "views: \{views.join(", ")}\n"
    for pname, p in comp.provide {
      sb <+ "provide: \{pname} = \{p.val}\n"
    }
    for lname, lk in comp.lookup {
      sb <+ "lookup: \{lname} = \{lk.comp_name}.\{lk.provide_name}\n"
    }
    let buckets : Array[String] = []
    for hname, _h in comp.receive {
      buckets.push("receive:\{hname}")
    }
    for hname, _h in comp.input {
      buckets.push("input:\{hname}")
    }
    for hname, _h in comp.bubble {
      buckets.push("bubble:\{hname}")
    }
    for hname, _h in comp.response {
      buckets.push("response:\{hname}")
    }
    if !buckets.is_empty() {
      sb <+ "handlers: \{buckets.join(", ")}\n"
    }
    sb <+ "\n"
  }
  ok(sb.to_string())
}

///|
fn run_render(
  m : @component.ModuleDef,
  args : ModArgs,
  opts : GlobalOpts,
  fmt : String,
) -> Emit raise {
  let scope = m.build_scope()
  let sb = StringBuilder()
  let rendered : Array[(String, String, String)] = [] // component, title, html
  for ex in m.examples {
    if args.name is Some(n) && ex.component != n {
      continue
    }
    if args.title is Some(t) && ex.title != t {
      continue
    }
    guard scope.lookup_component(ex.component) is Some(comp) else {
      return module_error(
        opts,
        "example '\{ex.title}' references unknown component '\{ex.component}'",
      )
    }
    let inst = comp.make(ex.args)
    let mut stack = @render.RenderStack::new(inst.to_value(), comps=scope.comps)
    let view_override = match args.view {
      Some(v) => Some(v)
      None => ex.view
    }
    match view_override {
      Some(v) => stack = stack.push_view_name(v)
      None => ()
    }
    let ctx = @render.RenderCtx::new(view_resolver=scope.comps)
    let html = match @render.render_root(inst.to_value(), stack, ctx) {
      Some(v) =>
        match @render.clean_vdom(v) {
          Some(clean) => {
            let doc = @memdom.document()
            @vdom.to_dom(clean, @vdom.RenderOpts::new(doc)).to_html()
          }
          None => "<!-- rendered nothing -->"
        }
      None => "<!-- rendered nothing -->"
    }
    rendered.push((ex.component, ex.title, html))
    sb <+ "## \{ex.component} — \{ex.title}\n\{html}\n\n"
  }
  if is_json(fmt) {
    return json_ok(
      Json::object({
        "examples": Json::array(
          rendered.map(r => {
            Json::object({
              "component": r.0.to_json(),
              "title": r.1.to_json(),
              "html": r.2.to_json(),
            })
          }),
        ),
      }),
    )
  }
  ok(sb.to_string())
}

///|
fn run_lint(
  m : @component.ModuleDef,
  args : ModArgs,
  fmt : String,
) -> Emit raise {
  let _scope = m.build_scope()
  let findings : Array[LintFinding] = []
  for comp in m.components {
    if args.name is Some(n) && comp.name != n {
      continue
    }
    findings.append(check_component(comp))
  }
  // exit code 2 signals error-level findings (JS result.hasErrors ? 2 : 0);
  // warnings/hints alone exit 0. The code is kept across formats.
  let has_errors = findings.iter().any(f => f.level is Error)
  let exit_code = if has_errors { 2 } else { 0 }
  if is_json(fmt) {
    let out = Json::object({
        "findings": Json::array(findings.map(f => f.to_json_value())),
      }).stringify(indent=2, escape_slash=false) +
      "\n"
    return { out, err: "", exit_code }
  }
  if findings.is_empty() {
    ok("no findings\n")
  } else {
    let sb = StringBuilder()
    for f in findings {
      sb <+ "\{f.line()}\n"
    }
    { out: sb.to_string(), err: "", exit_code }
  }
}

///|
pub fn plan_with_module(
  argv : Array[String],
  module_ : @component.ModuleDef?,
) -> Outcome {
  match module_ {
    None => plan(argv)
    Some(m) => {
      let (opts, rest) = match extract_globals(argv) {
        Ok(pair) => pair
        Err((opts, shape)) => return Done(error_emit(opts, shape))
      }
      guard rest.get(0) is Some(command) else { return plan(argv) }
      let command_args = rest.iter().drop(1).to_array()
      // module commands only; everything else keeps the plain dispatch
      // (help/feedback/agent-context/unknown-command handling)
      match find_command(command) {
        Some(cmd) if cmd.needs_module && !opts.help => {
          let args = parse_mod_args(command_args)
          // resolve the output format: explicit --format/--json, else the
          // command's default (JS emit() falls back to defaultFormat).
          let fmt = opts.format.unwrap_or(cmd.default_format.unwrap_or("cli"))
          let emit = try {
            match command {
              "get" => run_get(m, fmt)
              "list" => run_list(m, args, fmt)
              "examples" => run_examples(m, args, fmt)
              "show" => run_show(m, args, fmt)
              "render" => run_render(m, args, opts, fmt)
              "lint" => run_lint(m, args, fmt)
              _ => stub(command, ["not module-runnable yet"])
            }
          } catch {
            _ =>
              error_emit(
                opts,
                err(
                  CODE_INTERNAL,
                  "command '\{command}' failed on module '\{m.name}'",
                ),
              )
          }
          Done(emit)
        }
        _ => plan(argv)
      }
    }
  }
}
