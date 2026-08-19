///| A mounted dyncomp storybook, and everything it needs to keep running.
///
/// The gallery IS the page. Which stories exist, how they are filtered, what a
/// card shows and what "reset" means are all `dyncomp/storybook`,
/// backend-agnostic and driven by `moon test`; the floor under it — the loader
/// bar, `make_instance`, the margaui refresh — is `dyncomp/shell`, shared with
/// the universal host because both need exactly it and neither needs a
/// different one.
///
/// What is left here is this page's own: which module it mounts, what it lends
/// to what it hosts, and the entry points a page re-exports.
///
///   load a URL / drop a file -> @dhw.load_* -> the JS bridge instantiates the
///     guest -> dyncompLoaded -> the bar bubbles `catalogChanged`
///     -> the gallery re-reads the catalog and rebuilds every card
///
/// There is deliberately no session, unlike the universal host. A storybook has
/// nothing a person made: everything on it is a projection of what is loaded, so
/// the thing worth remembering is the BUNDLE, and that is what the sample
/// buttons and the URL box are for.

///|
/// A mounted gallery.
pub struct StorybookHost {
  app : @app.App[@wdom.WasmNode]
  gallery : @sb.Gallery
}

///|
/// Where the loader's answers arrive: the bar, which is the path that asked.
fn tools_path() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep("devTools")])
}

///|
/// The bar, with the one piece of bookkeeping a gallery has: a bundle that just
/// registered brought its own utility classes, and without recompiling them the
/// guest renders unstyled — which reads as a broken component rather than a
/// missing stylesheet.
fn tools_comp(samples : Array[@shell.LoaderBarSample]) -> @component.Component {
  @shell.loader_bar_comp(
    samples~,
    // A storybook is a place unfamiliar bundles get opened, so it takes one by
    // URL as well as by button. The universal host does not draw the box.
    show_url=true,
    status="drop a .tutuca.tar.gz, or load one by URL",
    notify=(ev, _ctx) => if ev is Loaded(_) { @shell.refresh_margaui() },
  )
}

///|
/// The module: the gallery, its chrome, and the bar.
///
/// One ModuleDef because one app mounts one module — and because the guest
/// components a bundle registers land in the same scope, which is what lets a
/// card's `<x render=".target">` resolve one. `requests` are the services this
/// HOST lends to what it hosts; a bundle that serves a request of the same name
/// answers its own components first.
pub fn storybook_module(
  samples? : Array[@shell.LoaderBarSample] = [],
  intents? : Map[String, Array[@component.IntentFn]] = {},
) -> (@component.ModuleDef, @sb.Gallery) {
  let (module_, gallery) = @sb.gallery_module(
    @dhw.registry(),
    @shell.make_instance,
    dev_tools="LoaderBar",
  )
  (
    @component.ModuleDef::new(
      name="dyncompstorybookwasm",
      components=[..module_.components, tools_comp(samples)],
      intents~,
    ),
    gallery,
  )
}

// --- lifecycle --------------------------------------------------------------

///|
/// Mount the storybook over the whole page.
///
/// `samples` are bundles to offer as buttons; empty draws none. `autoload`
/// fetches every one of them at mount, which is what a gallery shipped WITH its
/// bundles wants — a storybook that opens empty and asks you to press a button
/// first is a storybook with an extra step.
///
/// `requests` are services this page lends to what it hosts. A storybook needs
/// them for the same reason the editor does: a guest that asks the page for
/// something it cannot compute is showing a real part of itself, and a card
/// where that button does nothing is a card that lies about the component.
///
/// `policy` is what this page will accept from a bundle, and it defaults to
/// `untrusted`: no capabilities, no bundle CSS, stock quotas. Raising it is a
/// decision to make deliberately — see `dyncomp/SECURITY.md`. A storybook is
/// where an unfamiliar bundle gets opened, so the default matters more here than
/// almost anywhere.
///
/// Returns `None` if the app could not mount, which on wasm-gc means the page
/// had no `#app` to mount into.
pub fn mount(
  samples? : Array[@shell.LoaderBarSample] = [],
  autoload? : Bool = false,
  intents? : Map[String, Array[@component.IntentFn]] = {},
  policy? : @policy.Policy = @policy.Policy::untrusted(),
) -> StorybookHost? {
  let (module_, gallery) = storybook_module(samples~, intents~)
  guard @wglue.mount_in(module_, "DyncompStorybook") is Some(app) else {
    return None
  }
  @shell.set_live_app(app)
  @dhw.set_app(app, @wglue.document(), policy~)
  @shell.refresh_margaui()
  if autoload {
    for s in samples {
      @dhw.load_url(tools_path(), s.url) |> ignore
    }
  }
  Some({ app, gallery })
}

///|
/// Forward a DOM event into the app. A host exports this; JS calls it on every
/// event, since a MoonBit closure cannot cross into JS on wasm-gc.
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
/// Recompile + reinject margaui CSS. A page exports this for its loader to call
/// after a bundle lands; the bar already calls it, and the two are idempotent.
pub fn refresh_margaui() -> Unit {
  @shell.refresh_margaui()
}

///|
/// The gallery's whole state as text, for poking at the page from the console.
pub fn state_json() -> String {
  match @dhw.app_root_value() {
    Some(v) => v.to_display_string()
    None => "null"
  }
}
