// The storybook gallery as ONE generated tutuca component + the mount that
// wires every story's module into its own child scope.
//
// Layout: a left sidebar of grouped, clickable story titles drives a single
// `active` string field; each story has a `@show`-gated pane that renders its
// pre-built instance via `<x render=".sN">` (resolved by component id, so a
// foreign-scope instance renders fine) plus a collapsible Lint panel.

///|
/// Minimal HTML text escape for titles/section labels injected into the view.
fn esc(s : String) -> String {
  s
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
}

///|
/// Default lint callback: no findings. Hosts pass cli's check_component-backed
/// formatter to fill the Lint panel.
fn no_lint(_c : @component.Component) -> String {
  ""
}

///|
/// Generate the gallery root component from the grouped sections. Field naming
/// (`sN`/`lN`) follows the SAME nested iteration order `mount` uses, so indices
/// line up.
pub fn shell_component(sections : Array[@sb.Section]) -> @component.Component {
  let fields : Map[String, @component.FieldSpec] = {
    "active": @component.FieldSpec::of_default(Str("")),
  }
  let sb = StringBuilder::new()
  sb.write_string("<div class=\"flex min-h-screen\">")
  // sidebar
  sb.write_string(
    "<aside class=\"w-64 shrink-0 border-r border-base-300 p-3 overflow-y-auto\">",
  )
  sb.write_string("<h1 class=\"text-lg font-bold mb-3\">Storybook</h1>")
  for sec in sections {
    sb.write_string("<div class=\"mb-3\">")
    sb.write_string(
      "<div class=\"text-xs font-semibold uppercase opacity-50 mb-1\">\{esc(sec.title)}</div>",
    )
    for s in sec.stories {
      sb.write_string(
        "<a id=\"nav-\{s.id}\"" +
        " @if.class=\"equals? .active '\{s.id}'\"" +
        " @then=\"'block px-2 py-1 rounded text-sm cursor-pointer bg-primary text-primary-content'\"" +
        " @else=\"'block px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-200'\"" +
        " @on.click=\"$setActive '\{s.id}'\">\{esc(s.title)}</a>",
      )
    }
    sb.write_string("</div>")
  }
  sb.write_string("</aside>")
  // content panes
  sb.write_string("<main class=\"flex-1 p-4 overflow-y-auto\">")
  // fields whose example needs a host-dispatched `init` (see receive below)
  let init_fields : Array[String] = []
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      fields["s\{idx}"] = @component.FieldSpec::of_default(Null)
      fields["l\{idx}"] = @component.FieldSpec::of_default(Str(""))
      if s.renderable && s.init {
        init_fields.push("s\{idx}")
      }
      sb.write_string("<section @show=\"equals? .active '\{s.id}'\">")
      sb.write_string(
        "<h2 class=\"text-xl font-bold mb-1\">\{esc(s.title)}</h2>",
      )
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
  sb.write_string("</main></div>")
  // The gallery has no lifecycle of its own; when the host dispatches `init`
  // (see `mount`), forward it to each pane whose example loads data on init
  // (JS app.sendAtRoot("init") per pane). Mirrors the composability example's
  // init-forwarding to its child fields.
  let receive : Map[String, @component.InstanceHandler] = {
    "init": (inst, _args, ctx) => {
      for f in init_fields {
        ctx.send_at_path(ctx.path().concat([@tutuca.FieldStep(f)]), "init", [])
      }
      Some(inst)
    },
  }
  @component.component(name="Storybook", view=sb.to_string(), fields~, receive~)
}

///|
/// True when any story in `sections` needs a host-dispatched `init`.
fn needs_init(sections : Array[@sb.Section]) -> Bool {
  for sec in sections {
    for s in sec.stories {
      if s.renderable && s.init {
        return true
      }
    }
  }
  false
}

///|
/// Mount the gallery on `root_node`: register the shell in the root scope, each
/// story's module in its own child scope, pre-build each story instance from
/// that scope, seed them as the shell's `sN` fields, and start the app.
pub fn[N : @vdom.DomWalk] mount(
  sections : Array[@sb.Section],
  root_node : N,
  opts : @vdom.RenderOpts[N],
  lint? : (@component.Component) -> String = no_lint,
) -> @app.App[N] raise {
  let root_scope = @component.ComponentStack::new()
  let shell = shell_component(sections)
  root_scope.register_components([shell])
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
  // tutuca has no lifecycle: the host dispatches `init`, which the shell fans
  // out to the panes that load data on init (request-example, personal-site,
  // composability, …). Skip when no story needs it.
  if needs_init(sections) {
    app.send_at_root("init")
  }
  app
}
