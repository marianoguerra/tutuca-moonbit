///| The page, and the half of the demo a browser is needed for.
///
/// It holds three things nothing above it can: the component stack every module
/// registers into, the catalog the palette is a projection of, and the app.
/// Everything else — the picker, the keyboard, the cell memory, the pump — is
/// `demo/universal/ui`, driven on the in-memory DOM.

///|
/// What this page will accept from a card.
///
/// `granted` rather than `untrusted`, and the difference is one thing: an
/// untrusted module may carry no `<style>` block, and every component in the
/// kit has one. What it does NOT widen is what a module can do, because that is
/// settled before this runs: a module's import section is its complete
/// authority list, so a card importing anything the runtime does not export is
/// refused at instantiation whatever this says.
fn page_policy() -> @policy.Policy {
  @policy.Policy::granted()
}

///|
/// The one scope every module registers into.
///
/// One stack and not one per module: `register_module` enters a CHILD scope per
/// module, so names are isolated and ids are shared — which is exactly what
/// lets a hole from one card hold a component from another.
let scope : @component.ComponentStack = @component.ComponentStack::new()

///|
let catalog : @catalog.Catalog = @catalog.Catalog::new()

///|
let live : Ref[@app.App[@bdom.BrowserNode]?] = Ref(None)

///|
/// Say something on the page.
fn note(text : String, tone? : String = "") -> Unit {
  match live.val {
    Some(app) =>
      app.send_at_root("addNote", args=[Str(text), Str(tone)]) |> ignore
    None => println(text)
  }
}

///|
fn status(text : String) -> Unit {
  match live.val {
    Some(app) => app.send_at_root("setStatus", args=[Str(text)]) |> ignore
    None => ()
  }
}

///|
/// Compile a card and register it, under the name its own manifest gives.
///
/// The module key is the manifest's `moduleName` and never a name chosen here.
/// Choosing one is how a catalog comes to say `std` for a module the host
/// registered as something else, and then every component is findable and none
/// can be built.
pub fn load_card(source : String, label : String) -> Bool {
  let out = @emit.compile(source, name=label) catch {
    e => {
      note("\{label}: \{e.message()}", tone="error")
      return false
    }
  }
  let manifest_json = out.manifest.stringify()
  let key = manifest_module_name(out.manifest)
  if key == "" {
    note("\{label}: the manifest names no module", tone="error")
    return false
  }
  // Instantiating is the page's, because `WebAssembly.compile` answers a
  // promise and MoonBit cannot wait on one here. JS calls back into
  // `finish_load` when the module is running.
  begin_instantiate(key, @base64.encode(out.wasm), manifest_json)
  true
}

///|
/// The other half of `load_card`, called from JS once the module is up.
pub fn finish_load(key : String, manifest_json : String) -> String {
  match @guest.register(key, manifest_json, scope, page_policy()) {
    Err(reason) => {
      note("\{key}: \{reason}", tone="error")
      "refused"
    }
    Ok(loaded) => {
      catalog.add(
        @catalog.entries_of_manifest(
          @json.parse(manifest_json) catch {
            _ => Json::object({})
          },
          module_=key,
          annotations=if key == @std.module_name() {
            @std.annotations()
          } else {
            Map([])
          },
        ),
      )
      for line in loaded.diagnostics {
        note(line, tone="error")
      }
      // Both of these dispatch, which settles and re-renders — so a palette
      // that grew while the picker was open is visible without anyone typing.
      note("loaded \{key}")
      status("\{catalog.all().length()} components")
      if key == @std.module_name() {
        seed_canvas()
      }
      // A card that arrives now brings class names nothing has compiled, and a
      // component whose classes were never compiled renders unstyled rather
      // than failing — which is the kind of wrong that looks like a design.
      refresh_margaui()
      "ok"
    }
  }
}

///|
fn manifest_module_name(manifest : Json) -> String {
  match manifest {
    Object(o) =>
      match o.get("moduleName") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// What the builder needs from this page.
fn compose_host() -> @compose.ComposeHost {
  {
    make: (ref_, args) => @guest.make_instance(ref_.module_, ref_.name, args~),
    property: (v, name) => v.property_opt(name),
    // Separate from `make` so the walk never learns which module the holder
    // came from — and it is the KIT's hole, whoever made what goes in it.
    hole: held => {
      let args : Map[String, @tutuca.Value] = match held {
        Some(inner) => { "child": inner }
        None => Map([])
      }
      @guest.make_instance(@std.module_name(), "Hole", args~)
    },
  }
}

///|
/// Place one pick: build a one-node plan through the SAME builder a whole
/// arrangement uses.
///
/// A preset that opens a container at four cells is an arrangement of four
/// empty holes, and writing that twice is how the two would start disagreeing.
fn place_pick(argument : String) -> Unit {
  let (module_, component, preset) = @ui.pick_parts(argument)
  guard catalog.find(component, module_~) is Some(entry) else {
    note("nothing in the catalog is called \{component}", tone="error")
    @ui.forget_cell()
    return
  }
  let args : Map[String, Json] = Map([])
  let mut cells = 0
  if preset != "" {
    match entry.presets.iter().find_first(p => p.name == preset) {
      Some(chosen) => {
        for k, v in chosen.args {
          args[k] = v
        }
        cells = chosen.cells
      }
      None => ()
    }
  }
  let node : @compose.PlanNode = {
    ref_: entry.ref_,
    args,
    cells,
    children: [],
  }
  let (root, report) = @compose.build(compose_host(), node)
  for problem in report.problems {
    note(problem, tone="error")
  }
  guard root is Some(instance) else {
    @ui.forget_cell()
    return
  }
  guard live.val is Some(app) else { return }
  // Whether what is being placed draws its own settings travels BESIDE it, for
  // the hole to be told after it is holding it. It cannot ride on the instance:
  // `markEditable` is the HOLE's message and the thing being placed is a Grid,
  // which does not answer it — calling it there answers null, and a hole handed
  // null holds nothing, silently.
  app.send_at_root("placeBuilt", args=[instance, Bool(entry.is_editable())])
  |> ignore
}

///|
/// Search, and hand the rows back.
fn send_hits(query : String) -> Unit {
  guard live.val is Some(app) else { return }
  let hits = catalog
    .search(query)
    .map(hit => {
      (
        {
          component: hit.entry.ref_.name,
          module_: hit.entry.ref_.module_,
          preset: hit.preset,
          summary: hit.summary(),
          why: hit.why.join(", "),
        } : @ui.PickerHit)
    })
  app.send_at_root("pickerHits", args=[
    List(@ui.picker_rows(hits)),
    Str(@ui.empty_message(query, total=catalog.all().length())),
  ])
  |> ignore
}

///|
/// Drain the shell's one-slot pump.
///
/// The shell posts a verb and one argument and this answers; nothing here is
/// reachable from a view, which is the point of the pump existing at all.
pub fn drain(verb : String, argument : String) -> Unit {
  match verb {
    "search" => send_hits(argument)
    "place" => place_pick(argument)
    "load" => load_path(argument)
    "loadAll" => load_all()
    "loadChosen" => load_chosen()
    "compile" => if load_card(argument, "pasted") { status("compiling") }
    "save" => save()
    "restore" => restore()
    "clear" => clear_canvas()
    _ => ()
  }
  match live.val {
    Some(app) => app.send_at_root("pumped") |> ignore
    None => ()
  }
}
