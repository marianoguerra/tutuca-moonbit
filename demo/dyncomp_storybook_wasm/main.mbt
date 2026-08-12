///| The dyncomp storybook page: every component every loaded bundle declares,
/// once per configuration it declares.
///
/// Almost nothing is here. The gallery is `dyncomp/storybook`
/// (backend-agnostic, driven by `moon test`) and the host around it is
/// `dyncomp/storybook/wasm` — both published, so this file is what a consumer
/// copies rather than what they read for the machinery. What stays is the part
/// that is genuinely this page's: which bundles it offers, whether to fetch
/// them at once, what it accepts from one, and the wasm-gc export list.
///
/// An export list is per-package `link` configuration and cannot come from a
/// dependency, so the five entry points are re-exported here as one-line
/// forwards. That is the whole reason this is a package at all.

///|
fn main {

}

///|
/// The bundles `cmd/dev -- dyncomp-storybook` packs beside this page.
///
/// Unlike the universal demo, these are NOT behind a flag and they are fetched
/// at mount. The two pages want opposite first impressions: a universal host is
/// a blank page a person builds on, and meeting six buttons naming archives
/// they have never heard of would be wrong; a storybook is a gallery, and one
/// that opens empty and asks you to press a button first is a gallery with an
/// extra step.
fn samples() -> Array[@shell.LoaderBarSample] {
  [
    { label: "slack", url: "./examples/slack.tutuca.tar.gz" },
    { label: "bluesky", url: "./examples/bluesky.tutuca.tar.gz" },
    { label: "counter", url: "./examples/counter.tutuca.tar.gz" },
    { label: "todo", url: "./examples/todo.tutuca.tar.gz" },
    { label: "todomvc", url: "./examples/todomvc.tutuca.tar.gz" },
    { label: "calculator", url: "./examples/calculator.tutuca.tar.gz" },
    { label: "tic-tac-toe", url: "./examples/tictactoe.tutuca.tar.gz" },
    { label: "rust temp", url: "./examples/rust-tempconv.tutuca.tar.gz" },
  ]
}

// --- lifecycle exports ---------------------------------------------------

///|
/// Services this PAGE provides to whatever it hosts.
///
/// `double` is the one the sample counter calls (`control.request "double"`),
/// and a storybook needs it for the same reason the editor does: a card whose
/// button does nothing is a card that lies about the component. A bundle that
/// serves a request of the same NAME answers its own components first — the
/// counter's `triple` is its own and never reaches this map.
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

///|
pub fn mount() -> Unit {
  // `untrusted` is the default and this page keeps it deliberately: a
  // storybook is where an unfamiliar bundle gets opened, so it is the last
  // place to relax what a bundle may reach. Every sample above runs under it
  // unchanged.
  @sbw.mount(samples=samples(), autoload=true, requests=host_requests())
  |> ignore
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @sbw.on_event(ev)
}

///|
/// The JS bridge calls this once a dropped/fetched bundle is instantiated.
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @sbw.dyncomp_on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @sbw.dyncomp_on_load_error(load_id, msg)
}

///|
pub fn refresh_margaui() -> Unit {
  @sbw.refresh_margaui()
}

///|
pub fn state_json() -> String {
  @sbw.state_json()
}
