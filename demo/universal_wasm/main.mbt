///| Universal wasm-component host: drop a `.tutuca.tar.gz` bundle on the page
/// and mount any component it declares, styled with margaui utility classes.
///
/// Layout: a root shell (drop zone + status) renders one builtin ComponentList
/// — a flexbox canvas with a settings gear (layout controls) and an "add"
/// button. Each add appends a ComponentPicker; picking a component replaces
/// the picker with that component in place.
///
/// Message lifecycle (mirrors the parent app + its ComponentSelector):
///   ComponentList.onAdd            -> request "componentPicker"
///   .response."componentPicker"    -> append the picker, forward "init" to it
///     ComponentPicker.receive.init -> request "listComponents"
///     .response."listComponents"   -> build ComponentEntry rows into .items
///   click a row -> ComponentEntry bubbles "componentSelected" [module, name]
///     ComponentPicker.bubble       -> make_instance, set .selected (replaces
///                                     the picker chrome with the component)
///   drop a bundle -> shell.dyncompLoaded -> ComponentList.refresh
///                     -> re-init each picker so its list reflects the new bundle
///
/// The two request handlers ("listComponents", "componentPicker") are the
/// feature: one returns the registered components, the other hands back an
/// instance of the picker (which fetches the list itself, on init).

///|
fn main {

}

// --- ComponentEntry: one selectable row ---------------------------------

///|
fn component_entry_comp() -> @component.Component {
  component_entry_component(
    init={ module_: "", name: "", init_: "", label: "" },
    update=(s, msg, ctx) => {
      match ComponentEntryMsg::from_dispatch(msg) {
        Some(OnSelect) => {
          // the picker DECLARES this bubble, so the name and payload come from
          // its generated message rather than from a string written twice
          ComponentPickerBubble::ComponentSelected(s.module_, s.name, s.init_).bubble(
            ctx,
          )
          Some(s)
        }
        Some(Unknown(_, _)) | None => None
      }
    },
    // used by the picker's @when filter (called with the search text after the
    // dropped this-slot arg, like the parent app's matchesFilter)
    compute=m => {
      match m {
        ContainsText =>
          Some((s, args) => {
            match args {
              [Str(q), ..] => Bool(s.label.contains(q))
              _ => Bool(false)
            }
          })
      }
    },
  )
}

// --- ComponentPicker: selector that replaces itself with the pick --------

///|
/// Once `.selected` is set, the picker chrome is hidden and only the chosen
/// component renders — the picker "replaces itself". That is the views' doing,
/// and they come from component_picker.html through the generated wrapper.
fn component_picker_comp(entry : @component.Component) -> @component.Component {
  component_picker_component(
    init={ filterText: "", items: [], selected: Null },
    update=(s, msg, ctx) => {
      // The three channels this component uses are DECLARED in the state
      // block, so each arrives as a typed message instead of a name and a
      // list of Values to take apart by hand.
      match msg {
        // fetch the list of registered components on init (forwarded here when
        // the picker is added to a list)
        Receive("init", _) => {
          ctx.request(
            "listComponents",
            [],
            @tutuca.RequestOpts::new(on_ok_name="listComponents"),
          )
          Some(s)
        }
        _ =>
          match ComponentPickerResponse::from_dispatch(msg) {
            // the rows of registered components, as ComponentEntry instances
            Some(ListComponents(res)) =>
              Some({ ..s, items: entries_from_list(entry, res) })
            // the chosen component's instance came back — swap it in for the
            // picker chrome (the views key on `null? .selected`)
            Some(MakeComponent(Null)) => None
            Some(MakeComponent(v)) => Some({ ..s, selected: v })
            Some(Unknown(_, _)) | None =>
              // a bundle was reloaded: rebuild what this picker holds INTO the
              // new bundle, keeping its state. The instance says which
              // component it is — that is its declared schema's name — so the
              // picker needs to remember nothing about what it picked.
              match ComponentPickerReceive::from_dispatch(msg) {
                Some(Migrate(module_name)) =>
                  match s.selected {
                    Obj(o) =>
                      match o.obj_schema() {
                        Some(schema) =>
                          match
                            @dhw.migrate_instance(
                              module_name,
                              schema.name,
                              s.selected,
                            ) {
                            Some(next) => Some({ ..s, selected: next })
                            None => None
                          }
                        None => None
                      }
                    _ => None
                  }
                Some(Unknown(_, _)) | None =>
                  // a row was clicked: request that component's instance
                  match ComponentPickerBubble::from_dispatch(msg) {
                    Some(ComponentSelected(module_, name, init)) => {
                      ctx.stop_propagation()
                      ctx.request(
                        "makeComponent",
                        [Str(module_), Str(name), Str(init)],
                        @tutuca.RequestOpts::new(on_ok_name="makeComponent"),
                      )
                      Some(s)
                    }
                    Some(Unknown(_, _)) | None => None
                  }
              }
          }
      }
    },
    // @when predicate for render-each; keep rows whose entry's containsText
    // method matches the filter text
    when=w => {
      match w {
        MatchesFilter =>
          Some((s, _key, item, _iter) => {
            if s.filterText == "" {
              true
            } else {
              match item.field("containsText") {
                Fn(f) => f([Null, Str(s.filterText)]).is_truthy()
                _ => true
              }
            }
          })
      }
    },
  )
}

///|
/// Turn the "listComponents" result (rows of {module, name, label}) into
/// ComponentEntry instances for the picker's `items`.
fn entries_from_list(
  entry : @component.Component,
  res : @tutuca.Value,
) -> Array[@tutuca.Value] {
  match res {
    List(rows) =>
      rows.map(row => {
        match row {
          Map(m) =>
            entry.make({
              "module": m.get("module").unwrap_or(Str("")),
              "name": m.get("name").unwrap_or(Str("")),
              "init": m.get("init").unwrap_or(Str("")),
              "label": m.get("label").unwrap_or(Str("")),
            })
          _ => Null
        }
      })
    _ => []
  }
}

// --- ComponentList: the builtin flexbox canvas ---------------------------

///|
/// The gear (layout) and + (add) are subtle ghost icon buttons pinned to the
/// canvas corners via daisyUI's indicator; the canvas content is the
/// indicator's normal child. All of that is in the views the wrapper supplies.
fn component_list_comp() -> @component.Component {
  component_list_component(
    init={
      entries: [],
      showSettings: false,
      dir: "row",
      justify: "flex-start",
      align: "stretch",
      gap: 12,
      wrap: true,
    },
    update=(s, msg, ctx) => {
      match msg {
        // append a fresh picker: request one, seed + init it in the response
        Input("onAdd", _) => {
          ctx.request(
            "componentPicker",
            [],
            @tutuca.RequestOpts::new(on_ok_name="componentPicker"),
          )
          Some(s)
        }
        _ =>
          match ComponentListResponse::from_dispatch(msg) {
            Some(ComponentPicker(picker)) => {
              let entries = s.entries + [picker]
              let idx = entries.length() - 1
              // let the new picker fetch its component list (on init)
              ctx.send_at_path(
                ctx.path().concat([SeqStep(field="entries", key=KInt(idx))]),
                "init",
                [],
              )
              Some({ ..s, entries, })
            }
            Some(Unknown(_, _)) | None =>
              // a bundle loaded: re-init each picker so its list includes it
              match ComponentListReceive::from_dispatch(msg) {
                Some(Refresh) => {
                  for i in 0..<s.entries.length() {
                    ctx.send_at_path(
                      ctx.path().concat([SeqStep(field="entries", key=KInt(i))]),
                      "init",
                      [],
                    )
                  }
                  Some(s)
                }
                // a hot swap: every picker rebuilds what it holds
                Some(Migrate(module_name)) => {
                  for i in 0..<s.entries.length() {
                    ctx.send_at_path(
                      ctx.path().concat([SeqStep(field="entries", key=KInt(i))]),
                      "migrate",
                      [Str(module_name)],
                    )
                  }
                  Some(s)
                }
                Some(Unknown(_, _)) | None => None
              }
          }
      }
    },
    compute=m => {
      match m {
        // per-instance flexbox style from the settings fields (see visual_wasm
        // getInputWidth precedent for a compute returning a CSS string)
        FlexStyle =>
          Some((s, _args) => {
            let wrap = if s.wrap { "wrap" } else { "nowrap" }
            Str(
              "display:flex;flex-direction:\{s.dir};gap:\{s.gap}px;justify-content:\{s.justify};align-items:\{s.align};flex-wrap:\{wrap}",
            )
          })
      }
    },
  )
}

// --- root shell ----------------------------------------------------------

///|
fn universal_shell_comp() -> @component.Component {
  universal_wasm_component(
    init={
      ..UniversalWasmState::zero(),
      status: "drop a .tutuca.tar.gz bundle, then “+ Add component” to place it",
    },
    update=(s, msg, ctx) => {
      match msg {
        // A dropped file: `value` is the list of descriptors the drop event
        // carried, and the id names the file the browser still holds. No
        // page-level JS is involved — this is an ordinary input handler.
        // the same archive, fetched instead of dropped
        Input("loadSample", [Str(url), ..]) => {
          @dhw.load_url(ctx.path(), url) |> ignore
          Some({ ..s, status: "loading \{url}…" })
        }
        Input("loadDropped", [List(files), ..]) => {
          for f in files {
            match f.field("id") {
              Num(id) => @dhw.load_dropped(ctx.path(), id.to_int()) |> ignore
              _ => ()
            }
          }
          Some({ ..s, status: "loading…" })
        }
        _ =>
          match UniversalWasmReceive::from_dispatch(msg) {
            Some(DyncompLoaded(module_name)) => {
              let list_path = ctx.path().concat([FieldStep("list")])
              ctx.send_at_path(list_path, "refresh", [])
              // loading a module that was already registered is a HOT SWAP:
              // the components mounted from the old bundle rebuild into the
              // new one, keeping their state (Bundle::migrate_instance).
              ctx.send_at_path(list_path, "migrate", [Str(module_name)])
              Some({
                ..s,
                status: "loaded \{module_name} — add a component to place it",
              })
            }
            Some(DyncompError(m)) => Some({ ..s, status: "load failed: \{m}" })
            Some(Unknown(_, _)) | None => None
          }
      }
    },
  )
}

///|
/// Assemble the module: the components + the two request handlers the feature
/// adds. "listComponents" returns the registered components; "componentPicker"
/// hands back a picker instance.
fn universal_module() -> @component.ModuleDef {
  let entry = component_entry_comp()
  let picker = component_picker_comp(entry)
  let list = component_list_comp()
  let shell = universal_shell_comp()
  let requests : Map[String, @component.RequestFn] = {
    "listComponents": RequestFn((_args, respond) => {
      // the builtin flex list is always available (module "builtin"); the rest
      // are the components of loaded guest bundles
      let rows : Array[@tutuca.Value] = [
        Map({
          "module": Str("builtin"),
          "name": Str("ComponentList"),
          "init": Str(""),
          "label": Str("Flex list (builtin)"),
        }),
      ]
      for pair in @dhw.loaded_components() {
        let (m, n) = pair
        rows.push(
          Map({
            "module": Str(m),
            "name": Str(n),
            "init": Str(""),
            "label": Str("\{m} / \{n}"),
          }),
        )
        // ...and one row per NAMED initial state the component declares, so a
        // guest's fixtures are offered the way a host component's are
        for init in @dhw.component_inits(m, n) {
          rows.push(
            Map({
              "module": Str(m),
              "name": Str(n),
              "init": Str(init),
              "label": Str("\{m} / \{n} (\{init})"),
            }),
          )
        }
      }
      respond(Ok(List(rows)))
    }),
    "componentPicker": RequestFn((_args, respond) => {
      respond(Ok(picker.make(Map([]))))
    }),
    // A service the HOST provides to whatever it hosts: the sample counters
    // call it (control.request "double"). A bundle that serves a request of
    // the same name answers its own components first — see the counter
    // bundle's "triple".
    "double": RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("double: expected one number")))
      }
    }),
    // create a component instance by (module_, name): builtins natively, guest
    // components through the dyncomp bridge
    "makeComponent": RequestFn((args, respond) => {
      match args {
        [Str(m), Str(n), Str(init)] =>
          if m == "builtin" {
            match n {
              "ComponentList" => respond(Ok(list.make(Map([]))))
              _ => respond(Err(Str("unknown builtin \{n}")))
            }
          } else {
            // a named fixture when the row carried one, a bare instance
            // otherwise
            let made = if init == "" {
              @dhw.make_instance(m, n)
            } else {
              @dhw.make_init(m, n, init)
            }
            match made {
              Some(v) => respond(Ok(v))
              None => respond(Err(Str("could not make \{m}/\{n}")))
            }
          }
        _ => respond(Err(Str("makeComponent: expected [module_, name, init]")))
      }
    }),
  }
  @component.ModuleDef::new(
    name="universalwasm",
    components=[shell, list, picker, entry],
    requests~,
  )
}

// --- margaui class publishing -------------------------------------------

///|
let app_ref : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
/// Compile the app's utility-class set to CSS in MoonBit (via the
/// marianoguerra/tailwindcss port) and inject it as <style id="margaui-css">
/// (mirrors demo/storybook_wasm). Called at mount and again (via the exported
/// refresh_margaui) after a bundle loads, so guest-view classes get compiled
/// too. index.html pre-places an empty <style id="margaui-css"> early in <head>
/// so the upsert keeps it ahead of any lazily-loaded palette <link>.
fn apply_margaui() -> Unit {
  guard app_ref.val is Some(app) else { return }
  let css = @css.compile_margaui(app.scope.comps.collect_classes()) catch {
    err => {
      @tutuca.warn("margaui compile failed: \{err}")
      return
    }
  }
  @wglue.inject_style(@wglue.document(), "margaui-css", css)
}

///|
/// Recompile + reinject margaui CSS after a guest bundle registers new views
/// (and thus new utility classes). Exported; the loader calls it post-load.
pub fn refresh_margaui() -> Unit {
  apply_margaui()
}

// --- lifecycle exports ---------------------------------------------------

///|
pub fn mount() -> Unit {
  guard @wglue.mount_in(universal_module(), "UniversalWasm") is Some(app) else {
    return
  }
  app_ref.val = Some(app)
  @dhw.set_app(app, @wglue.document())
  apply_margaui()
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @dhw.on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @dhw.on_load_error(load_id, msg)
}

///|
/// Root state as display text, for inspection/automated verification.
///
/// Deliberately NOT `to_json`, unlike the playground's panel: this tree holds
/// GUEST instances, and a guest declares no fields (the manifest carries none
/// yet), so `to_json` would project them to null. `obj_debug` reaches the
/// guest's own `to-json` projection instead. Once the manifest carries a field
/// list this can move over with the rest.
pub fn state_json() -> String {
  guard @dhw.app_root_value() is Some(v) else { return "null" }
  v.to_display_string()
}
