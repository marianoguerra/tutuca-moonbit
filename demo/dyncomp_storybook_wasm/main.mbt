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
    { label: "mastodon", url: "./examples/mastodon.tutuca.tar.gz" },
    { label: "counter", url: "./examples/counter.tutuca.tar.gz" },
    { label: "todo", url: "./examples/todo.tutuca.tar.gz" },
    { label: "todomvc", url: "./examples/todomvc.tutuca.tar.gz" },
    { label: "calculator", url: "./examples/calculator.tutuca.tar.gz" },
    { label: "tic-tac-toe", url: "./examples/tictactoe.tutuca.tar.gz" },
    { label: "table", url: "./examples/table.tutuca.tar.gz" },
    { label: "rust temp", url: "./examples/rust-tempconv.tutuca.tar.gz" },
  ]
}

// --- lifecycle exports ---------------------------------------------------

///|
pub fn mount() -> Unit {
  // `untrusted` and one grant, which is `@shell.sample_policy`: no clock, no
  // timer, no entropy, no CSS of a bundle's own, and `cap-external-urls` for
  // the five origins the bundles above load a picture or point a link at. A
  // storybook is where an unfamiliar bundle gets opened, so the tier stays
  // where it was — what changed is that this page ships two readers whose
  // subject is other people's pictures, and it can name where those come from
  // rather than making them draw initials forever.
  //
  // A DROPPED bundle gets the same answer, which is the part to be deliberate
  // about: it may pin an `<img src>` at those five origins too. What it may
  // not do is choose an origin, so what that buys an unknown bundle is the
  // ability to tell one of five hosts that this page loaded something.
  @sbw.mount(
    samples=samples(),
    autoload=true,
    requests=@shell.sample_host_requests(),
    policy=@shell.sample_policy(),
  )
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
