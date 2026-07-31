///| Universal wasm-component host: drop a `.tutuca.tar.gz` bundle on the page,
/// search what it declared, fill in a form, and arrange what you placed.
///
/// The page is a shell around `dyncomp/ui`. Everything the editor does —
/// the catalog search, the schema-generated form, the layout algebra, import
/// and export — is backend-agnostic and driven by `moon test`; what is here is
/// the part that cannot be, which is the bridge that turns an archive into
/// registered components and a `ComponentRef` into a live guest instance.
///
///   drop / load a URL -> @dhw.load_* -> the JS bridge instantiates the guest
///     -> dyncomp_on_loaded -> register_bundle + @dhw.registry().register
///     -> shell.dyncompLoaded -> editor.catalogChanged (the palette re-runs)
///
///   pick in the palette -> the editor generates a form from the component's
///     declared arguments -> place -> `make_instance` through the bridge
///     -> BindInstance into the surface document

///|
fn main {

}

///|
/// Build a guest instance for the editor to place.
///
/// The one thing `dyncomp/ui` cannot do for itself: a named fixture goes
/// through `make_init`, everything else through the bare constructor with the
/// arguments the form validated.
fn make_instance(
  ref_ : @registry.ComponentRef,
  init : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value? {
  let made = if init == "" {
    @dhw.make_instance(ref_.module_, ref_.name, args~)
  } else {
    @dhw.make_init(ref_.module_, ref_.name, init)
  }
  match made {
    Some(v) => Some(v)
    None => None
  }
}

///|
/// The page shell: a drop target, a status line, and the editor.
///
/// `editor` is a NAMED slot, so the framework constructs it from the editor's
/// own `init` — an empty surface with its palette already showing the catalog.
/// Nothing here has to know what a seeded editor looks like.
fn universal_shell_comp(
  seed : Map[String, @tutuca.Value],
) -> @component.Component {
  universal_wasm_component(
    init={
      status: "drop a .tutuca.tar.gz bundle, or load one of the samples",
      editor: Null,
    },
    // The state block cannot NAME this slot: `surface-editor` is declared in
    // another package, and the generator resolves a sibling component only
    // within one file — so the schema says `component` and `slots~` is what
    // fills in which one. `slot_args~` then carries what it is built with,
    // because a component-typed field takes its value from construction args
    // rather than from `init`.
    slots={ "editor": "SurfaceEditor" },
    slot_args={ "editor": seed },
    update=(s, msg, ctx) => {
      match msg {
        // A dropped file: `value` is the list of descriptors the drop event
        // carried, and the id names the file the browser still holds. No
        // page-level JS is involved — this is an ordinary input handler.
        Input("loadDropped", [List(files), ..]) => {
          for f in files {
            match f.field("id") {
              Num(id) => @dhw.load_dropped(ctx.path(), id.to_int()) |> ignore
              _ => ()
            }
          }
          Some({ ..s, status: "loading…" })
        }
        // the same archive, fetched instead of dropped
        Input("loadSample", [Str(url), ..]) => {
          @dhw.load_url(ctx.path(), url) |> ignore
          Some({ ..s, status: "loading \{url}…" })
        }
        _ =>
          match UniversalWasmReceive::from_dispatch(msg) {
            // The catalog changed under whatever the palette is showing, so
            // the editor is told rather than left stale. A reload of a module
            // already registered is a HOT SWAP: the registry replaces it in
            // place, keeping its position in the palette.
            Some(DyncompLoaded(module_name)) => {
              ctx.send_at_path(
                ctx.path().concat([FieldStep("editor")]),
                "catalogChanged",
                [Str(module_name)],
              )
              Some({ ..s, status: "loaded \{module_name}" })
            }
            // The refusal's own words: "this host takes no CSS from a bundle",
            // "no such component". A generic sentence here would throw away
            // the one thing a person can act on.
            Some(DyncompError(why)) => Some({ ..s, status: why })
            Some(Unknown(_, _)) | None => None
          }
      }
    },
  )
}

///|
/// The module: the editor's components plus this page's shell.
///
/// One ModuleDef because one app mounts one module — and because the guest
/// components a bundle registers land in the same scope, which is what lets
/// `<x render=".slot">` resolve them.
fn universal_module() -> @component.ModuleDef {
  let (editor_module, seed) = @ui.seeded_editor(@dhw.registry(), make_instance)
  @component.ModuleDef::new(
    name="universalwasm",
    components=[universal_shell_comp(seed)] + editor_module.components,
    requests=host_requests(),
  )
}

///|
/// Services this HOST provides to whatever it hosts.
///
/// `double` is the one the sample counter calls (`control.request "double"`),
/// and it is here to demonstrate the seam rather than because doubling is
/// interesting: it is a guest asking the page for something it cannot compute
/// for itself. A bundle that serves a request of the same NAME answers its own
/// components first — the counter's `triple` is served by its own bundle and
/// never reaches this map.
///
/// Whether a guest should be able to reach these at all is the open question
/// in dyncomp/SECURITY.md §5: the answer wants the requester's path, which
/// `RequestFn` does not carry yet.
fn host_requests() -> Map[String, @component.RequestFn] {
  {
    "double": RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("double: expected one number")))
      }
    }),
  }
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
/// The JS bridge calls this once a dropped/fetched bundle is instantiated.
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
/// The app's whole state as JSON, for poking at the page from the console.
pub fn state_json() -> String {
  match @dhw.app_root_value() {
    Some(v) => v.to_display_string()
    None => "null"
  }
}
