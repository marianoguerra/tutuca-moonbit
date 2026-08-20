///| The app: the one component that hears every request and answers it.
///
/// Every route here has the same shape — a component asked for something, and
/// `ctx.target_path()` says which one asked. That is what replaces the node
/// ids a document would have had, and it is strictly better: it reaches inside
/// a guest's own placeholder, which no document ever could.
///
/// Asking and answering are two dispatches, deliberately. A `+` opens a bar
/// over the whole page; the choice comes later, out of a different click, and
/// still lands in the cell that asked. Holding the path is the whole mechanism.

///|
/// Open the bar aimed at whoever asked.
fn UniversalUi::open_bar(
  self : UniversalUi,
  s : UniversalAppState,
  at : @tutuca.DispatchPath,
  configure~ : Bool,
) -> @component.Update[UniversalAppState] {
  self.asked.val = Some(at)
  Next({
    ..s,
    commandBar: self.bar_for("", configure~),
    status: if configure {
      "pick one, and fill in its arguments"
    } else {
      "pick one"
    },
  })
}

///|
fn UniversalUi::close_bar(
  self : UniversalUi,
  s : UniversalAppState,
) -> @component.Update[UniversalAppState] {
  self.asked.val = None
  Next({ ..s, commandBar: Null, status: "" })
}

///|
/// Put `inst` where the last request came from.
///
/// None of "where" is stored in the state: the path is on the app, and the
/// message goes to it. A cell that has moved since it asked is a cell this
/// misses — which is why the bar is modal, and why nothing else can edit the
/// tree while it is open.
fn UniversalUi::deliver(
  self : UniversalUi,
  ctx : &@tutuca.Ctx,
  inst : @tutuca.Value,
) -> Bool {
  guard self.asked.val is Some(at) else { return false }
  ctx.send_at_path(at, "hold", [inst])
  self.asked.val = None
  true
}

///|
/// Place a component with nothing filled in.
///
/// Three ways this fails and each says something different: nothing in the
/// catalog answers to that name, the schema will not accept the defaults (a
/// required argument with no default — so ASK, by opening the form), or the
/// thing could not be built at all (the bridge's problem, into the status
/// line).
fn UniversalUi::place_default(
  self : UniversalUi,
  s : UniversalAppState,
  ctx : &@tutuca.Ctx,
  ref_ : @registry.ComponentRef,
) -> @component.Update[UniversalAppState] {
  guard self.registry.describe(ref_) is Some(d) else {
    return Next({ ..s, status: "no such component: \{ref_.to_id()}" })
  }
  match defaults_of(d) {
    // It needs something nobody has said yet. Opening the form is the answer
    // rather than an error: the person asked for this component, and the form
    // is how they get it.
    Err(_) =>
      Next({
        ..s,
        commandBar: Null,
        configPanel: self.make_("ConfigPanel", {
          "title": Str(d.ref_.to_id()),
          "mode": Str("form"),
          "target": Null,
          "form": self.form_for(d),
        }),
        status: "\{d.ref_.to_id()} needs some arguments",
      })
    Ok(args) =>
      match self.build(ref_, args) {
        Some(inst) => {
          if !self.deliver(ctx, inst) {
            return Next({ ..s, commandBar: Null, status: "nowhere to put it" })
          }
          Next({ ..s, commandBar: Null, status: "placed \{ref_.to_id()}" })
        }
        None =>
          Next({
            ..s,
            commandBar: Null,
            status: "could not build \{ref_.to_id()}",
          })
      }
  }
}

///|
/// Validate a filled-in form and place what it describes.
fn UniversalUi::place_form(
  self : UniversalUi,
  s : UniversalAppState,
  ctx : &@tutuca.Ctx,
  ref_ : @registry.ComponentRef,
  init : String,
  fields : Array[@tutuca.Value],
) -> @component.Update[UniversalAppState] {
  guard self.registry.describe(ref_) is Some(d) else {
    return Next({ ..s, status: "no such component: \{ref_.to_id()}" })
  }
  // A named fixture is the component's own answer to "what arguments", so the
  // blank form beside it is not consulted — but it has to be RESOLVED here, to
  // the arguments it names.
  //
  // Leaving it to whatever builds the component is what used to break: placing
  // CONSTRUCTS and reconfiguring WRITES THROUGH, and only the first of those can
  // be handed a fixture NAME. The second writes the map field by field, so the
  // empty map this used to pass meant "write nothing" — which a per-field write
  // cannot tell apart from "nothing changed". The panel closed and the fixture
  // silently did nothing.
  //
  // `InitInfo::args` is already decoded host-side, for a loaded bundle as much
  // as a standard component, so resolving costs nothing and nothing crosses the
  // boundary to do it.
  let args = if init != "" {
    match d.inits.filter(i => i.name == init) {
      [chosen, ..] => chosen.args
      // The fixture is gone — a bundle hot-swapped under an open panel is the
      // way that happens. Saying so beats quietly placing the defaults.
      _ =>
        return Next({
          ..s,
          status: "\{ref_.to_id()} has no fixture \"\{init}\"",
        })
    }
  } else {
    match d.coerce_args(form_args(fields)) {
      Ok(a) => a
      Err(errors) => {
        let by_pointer : Map[String, @tutuca.Value] = Map([])
        for e in errors {
          by_pointer[e.pointer] = Str(e.message)
        }
        ctx.send_at_path(
          ctx.path().concat([FieldStep("configPanel"), FieldStep("form")]),
          "showErrors",
          [Map(by_pointer)],
        )
        return Next({ ..s, status: "check the highlighted fields" })
      }
    }
  }
  // Reconfiguring rather than placing. Either way the fields are WRITTEN
  // THROUGH rather than used to rebuild, so everything the schema does not
  // name — a half-typed sentence, a scroll position, whatever a guest keeps
  // privately — survives a change to what it does.
  if self.configuring.val is Some(at) {
    let held = s.configPanel.field("target")
    if held is Obj(_) {
      // `view` mode: the panel is holding it, so write here and hand it back.
      let mut next = held
      for name, v in args {
        next = next.with_field(name, v)
      }
      return self.close_config(s, ctx, put_back=next)
    }
    // `form` mode: it never left the tree, so the write goes to the cell that
    // holds it. The app knows the fields are valid; only the universal knows
    // which instance they belong to.
    ctx.send_at_path(at, "applyConfig", [Map(args)])
    return self.close_config(s, ctx)
  }
  match self.build(ref_, args) {
    Some(inst) => {
      if !self.deliver(ctx, inst) {
        return Next({ ..s, configPanel: Null, status: "nowhere to put it" })
      }
      Next({ ..s, configPanel: Null, status: "placed \{ref_.to_id()}" })
    }
    None => Next({ ..s, status: "could not build \{ref_.to_id()}" })
  }
}

// --- the sidebar ------------------------------------------------------------

///|
/// Open the sidebar for whatever a universal is holding.
///
/// Two modes, and the choice is made by asking the instance what views it
/// declared — the same question of a guest and of a standard component,
/// answered off the schema either of them carries.
///
/// A component with a `config` view of its own gets it rendered LIVE, and that
/// costs something the UI has to be honest about: an instance rendered in two
/// places has one of them holding a handle the host has already collected, so
/// it is MOVED here and the cell it came from shows a placeholder until the
/// panel closes. Everything else gets the generated form, and stays where it
/// is — which is the common case, and the one where you watch the change land.
fn UniversalUi::open_config(
  self : UniversalUi,
  s : UniversalAppState,
  ctx : &@tutuca.Ctx,
  child : @tutuca.Value,
) -> @component.Update[UniversalAppState] {
  let at = ctx.target_path()
  guard child is Obj(_) else {
    // An empty cell has nothing to configure, so offer to fill it instead.
    return self.open_bar(s, at, configure=false)
  }
  let title = match child.schema() {
    Some(sc) => sc.name
    None => "component"
  }
  let declares_config = match child.schema() {
    Some(sc) => sc.view_names.contains("config")
    None => false
  }
  if declares_config {
    self.configuring.val = Some(at)
    ctx.send_at_path(at, "empty", [])
    return Next({
      ..s,
      configPanel: self.make_("ConfigPanel", {
        "title": Str(title),
        "mode": Str("view"),
        "target": child,
        "form": Null,
      }),
      status: "configuring \{title}",
    })
  }
  guard self.describe_instance(child) is Some(d) else {
    return Next({ ..s, status: "nothing is known about \{title}" })
  }
  // The form opens on what the instance ALREADY holds, so changing one
  // property does not mean retyping the rest.
  let values : Map[String, @tutuca.Value] = Map([])
  for f in d.schema.fields {
    values[f.name] = child.field(f.name)
  }
  self.configuring.val = Some(at)
  Next({
    ..s,
    configPanel: self.make_("ConfigPanel", {
      "title": Str(d.ref_.to_id()),
      "mode": Str("form"),
      "target": Null,
      "form": self.form_for(d, values~, submit_label="Apply"),
    }),
    status: "configuring \{d.ref_.to_id()}",
  })
}

///|
/// Close the sidebar, putting back whatever it took.
///
/// `put_back` is the instance as it now is — the one the panel has been
/// rendering, or the one an Apply just wrote through. Reading it out of the
/// panel rather than remembering it here is the same rule the rest of this
/// follows: the tree is the state, and the panel is part of the tree.
fn UniversalUi::close_config(
  self : UniversalUi,
  s : UniversalAppState,
  ctx : &@tutuca.Ctx,
  put_back? : @tutuca.Value = Null,
) -> @component.Update[UniversalAppState] {
  let restored = if put_back is Null {
    s.configPanel.field("target")
  } else {
    put_back
  }
  match (self.configuring.val, restored) {
    (Some(at), Obj(_)) => ctx.send_at_path(at, "hold", [restored])
    _ => ()
  }
  self.configuring.val = None
  Next({ ..s, configPanel: Null, status: "" })
}

// --- the app ----------------------------------------------------------------

///|
/// A bundle loaded, so the catalog changed under whatever the bar is showing.
/// Re-running the search is cheaper than telling a person to retype it.
fn UniversalUi::catalog_changed(
  self : UniversalUi,
  s : UniversalAppState,
  module_ : String,
) -> @component.Update[UniversalAppState] {
  let bar = if s.commandBar is Obj(_) {
    self.bar_for(
      s.commandBar.field("query").str(),
      configure=s.commandBar.field("configure").is_truthy(),
    )
  } else {
    Null
  }
  Next({ ..s, commandBar: bar, status: "loaded \{module_}" })
}

///|
/// A whole page, from wherever the host keeps them.
fn restore_tree(
  s : UniversalAppState,
  root : @tutuca.Value,
) -> @component.Update[UniversalAppState] {
  if root is Obj(_) {
    Next({ ..s, root, status: "restored" })
  } else {
    Next({ ..s, status: "could not restore the last page" })
  }
}

///|
fn UniversalUi::app_comp(
  self : UniversalUi,
  dev_tools~ : String,
) -> @component.Component {
  universal_app_component(
    // The host's own component in the bar, named at the seam because the
    // generator resolves a sibling only within one file and this one lives
    // wherever the host is.
    slots=if dev_tools == "" { Map([]) } else { { "devTools": dev_tools } },
    init={
      ..UniversalAppState::zero(),
      mode: "edit",
      status: "click the + to choose what this page is",
    },
    compute=m => {
      match m {
        ModeLabel =>
          Some((s, _args) => {
            Str(if s.mode == "edit" { "editing" } else { "viewing" })
          })
      }
    },
    update=(s, msg, ctx) => {
      match UniversalAppMsg::from_dispatch(msg) {
        // With nothing having asked, the bar aims at the root — which is the
        // only cell there is when a page is new.
        Some(OpenCommand) =>
          return self.open_bar(
            s,
            ctx.path().concat([FieldStep("root")]),
            configure=false,
          )
        Some(ToggleMode) =>
          return Next({
            ..s,
            mode: if s.mode == "edit" {
              "main"
            } else {
              "edit"
            },
          })
        // Files dropped on the page. Forwarded to whatever the host put in
        // the bar, because reading one is exactly the kind of thing a
        // backend-agnostic package cannot do.
        Some(FilesDropped(_)) => {
          // The generator types `value` as text, because it reads the host
          // element's static `type` and a `<div>` has none. What actually
          // arrives is the list of dropped files, so it is read raw.
          let files = match msg {
            Receive(_, [first, ..]) => first
            _ => Null
          }
          ctx.send_at_path(
            ctx.path().concat([FieldStep("devTools")]),
            "filesDropped",
            [files],
          )
          return Unhandled
        }
        Some(Unknown(_, _)) | None => ()
      }
      match UniversalAppReceive::from_dispatch(msg) {
        Some(CatalogChanged(module_)) => return self.catalog_changed(s, module_)
        Some(RestoreTree(root)) => return restore_tree(s, root)
        // The merged `Receive` now carries this component's own VIEW names as
        // well as the schema's, so `Unknown` no longer covers everything this
        // match has nothing to say about. They are answered by the match
        // beside this one.
        _ => ()
      }
      match msg {
        // A `+` was clicked. `target_path` is the cell that asked, fixed for
        // the whole bubble however many components it passed on the way up.
        Intent("addRequested", [flag, ..]) => {
          ctx.stop_propagation()
          self.open_bar(s, ctx.target_path(), configure=flag.is_truthy())
        }
        Intent("configRequested", [child, ..]) => {
          ctx.stop_propagation()
          self.open_config(s, ctx, child)
        }
        Intent("queryChanged", [Str(q), ..]) => {
          ctx.stop_propagation()
          Next({
            ..s,
            commandBar: self.bar_for(
              q,
              configure=s.commandBar.field("configure").is_truthy(),
            ),
          })
        }
        Intent("commandClose", _) => {
          ctx.stop_propagation()
          self.close_bar(s)
        }
        Intent("componentPicked", [Str(module_), Str(name), flag, ..]) => {
          ctx.stop_propagation()
          let ref_ : @registry.ComponentRef = { module_, name }
          // Two ways to ask for the form and either will do: ctrl/cmd on THIS
          // click, or a bar that was opened in configure mode to begin with.
          // A bar opened by ctrl-clicking a `+` and then used with plain
          // clicks would otherwise quietly stop configuring.
          let configure = flag.is_truthy() ||
            s.commandBar.field("configure").is_truthy()
          if configure {
            // Configure first: the form, over the same schema the catalog
            // projects, with the defaults already in it.
            match self.registry.describe(ref_) {
              Some(d) =>
                Next({
                  ..s,
                  commandBar: Null,
                  configPanel: self.make_("ConfigPanel", {
                    "title": Str(d.ref_.to_id()),
                    "mode": Str("form"),
                    "target": Null,
                    "form": self.form_for(d),
                  }),
                  status: "fill in \{d.ref_.to_id()} and place it",
                })
              None =>
                Next({ ..s, status: "no such component: \{ref_.to_id()}" })
            }
          } else {
            self.place_default(s, ctx, ref_)
          }
        }
        Intent("submitForm", [Str(module_), Str(name), Str(init), List(fields)]) => {
          ctx.stop_propagation()
          self.place_form(s, ctx, { module_, name }, init, fields)
        }
        Intent("cancelForm", _) | Intent("closeConfig", _) => {
          ctx.stop_propagation()
          self.close_config(s, ctx)
        }
        // The same two the receives above answer, arriving the other way.
        // Whatever the host put in the bar is a CHILD of this component, so
        // what it has to say comes up as a bubble — and a host that drives the
        // app from outside sends the same names down. One pair of names, two
        // directions, one implementation.
        Intent("catalogChanged", [Str(module_), ..]) => {
          ctx.stop_propagation()
          self.catalog_changed(s, module_)
        }
        Intent("restoreTree", [root, ..]) => {
          ctx.stop_propagation()
          restore_tree(s, root)
        }
        // Files, from a CELL that did not want them: `drop` stops at the first
        // component that handles it, so a universal has to hand back what is
        // not its.
        Intent("filesDropped", args) => {
          ctx.send_at_path(
            ctx.path().concat([FieldStep("devTools")]),
            "filesDropped",
            args,
          )
          Unhandled
        }
        _ => Unhandled
      }
    },
  )
}

///|
/// The app's module: the chrome, the app, and every standard component.
///
/// One `ModuleDef` because one app mounts one module — and because a loaded
/// bundle's components land in the same scope, which is what lets an
/// `<x render=".child">` inside a universal resolve one.
///
/// `dev_tools` names a component the HOST supplies for the bar — loading
/// bundles, in the wasm shell's case. Empty for a host that needs none, which
/// is every test.
pub fn universal_module(
  registry : @registry.Registry,
  make : MakeInstance,
  dev_tools? : String = "",
) -> @component.ModuleDef {
  seeded_app(registry, make, dev_tools~).0
}

///|
/// The module AND the `UniversalUi` behind it.
///
/// A host that only mounts needs the first half. One that also restores a
/// saved page needs the second, because rebuilding a standard component by
/// name is something only the thing holding them can do — and building a
/// second `Std` would hand back look-alikes the mounted scope cannot resolve.
pub fn seeded_app(
  registry : @registry.Registry,
  make : MakeInstance,
  dev_tools? : String = "",
) -> (@component.ModuleDef, UniversalUi) {
  let (std_comps, std) = @std.std_components()
  let ui : UniversalUi = {
    registry,
    make,
    std,
    comps: Map([]),
    asked: { val: None },
    configuring: { val: None },
  }
  // The catalog answers for the standard components as soon as it exists, so
  // a page with no bundles loaded is still one you can build.
  registry.set_builtins(builtin_descriptors(std_comps))
  // Leaves first, and not for tidiness: the app's `init` and its handlers
  // build rows, fields, forms and panels out of them, so `comps` has to hold
  // them by the time any of that runs.
  let chrome = [
    palette_row_comp(),
    command_bar_comp(),
    schema_field_comp(),
    schema_form_comp(),
    config_panel_comp(),
  ]
  for c in chrome {
    ui.comps[c.name] = c
  }
  let app = ui.app_comp(dev_tools~)
  ui.comps[app.name] = app
  (
    @component.ModuleDef::new(
      name="universalui",
      components=[app, ..chrome, ..std_comps],
    ),
    ui,
  )
}
