///| Universal wasm-component demo: drop a `.tutuca.tar.gz` bundle on the page,
/// search what it declared, and build a page out of it.
///
/// Almost nothing is here. The editor is `dyncomp/ui` (backend-agnostic, driven
/// by `moon test`) and the host around it is `dyncomp/ui/wasm` — both published,
/// so this file is what a consumer copies rather than what they read for the
/// machinery. What stays is the part that is genuinely this page's: which
/// bundles it offers, whether it remembers a session, and the wasm-gc export
/// list. (The sample `double` service it lends to what it hosts is
/// `@shell.sample_host_intents` — the storybook page offers the same one.)
///
/// An export list is per-package `link` configuration and cannot come from a
/// dependency, so the five entry points are re-exported here as one-line
/// forwards. That is the whole reason this is a package at all.

///|
fn main {

}

///|
/// Whether this page was opened for working ON it rather than for using it —
/// `?test` in the query string.
///
/// It gates two things, and they belong together: the sample-loading buttons,
/// and the SESSION. A first-time visitor should meet an empty page and a `+`,
/// not six buttons naming archives they have never heard of and whatever the
/// last person left behind.
///
/// Read once, because `location` cannot change under a page that never
/// navigates, and a flag read twice is a flag that can disagree with itself.
let dev_mode : Bool = has_test_param()

///|
/// `?test`, `?test=1`, `?a=1&test` — but not `?testing` or `?x=test`, which is
/// why this looks at parameter NAMES rather than at the string.
fn has_test_param() -> Bool {
  let loc = @core.global_this()._get("location")
  if @core.is_nullish(loc) {
    return false
  }
  let search = loc._get("search")
  if @core.is_nullish(search) {
    return false
  }
  let query = search.to_string()
  let body = if query.has_prefix("?") { query[1:].to_owned() } else { query }
  for part in body.split("&") {
    let pair = part.to_owned()
    let name = match pair.find("=") {
      Some(i) => pair[0:i].to_owned()
      None => pair
    }
    if name == "test" {
      return true
    }
  }
  false
}

///|
/// The bundles `cmd/dev -- universal` packs beside this page. Behind `?test`
/// because they are for working on the demo rather than for using it; dropping
/// a bundle is not gated, because that is what the page is for.
fn samples() -> Array[@shell.LoaderBarSample] {
  if !dev_mode {
    return []
  }
  [
    { label: "counter", url: "./examples/counter.tutuca.tar.gz", },
    { label: "todo", url: "./examples/todo.tutuca.tar.gz", },
    { label: "todomvc", url: "./examples/todomvc.tutuca.tar.gz", },
    { label: "calculator", url: "./examples/calculator.tutuca.tar.gz", },
    { label: "tic-tac-toe", url: "./examples/tictactoe.tutuca.tar.gz", },
    { label: "bluesky", url: "./examples/bluesky.tutuca.tar.gz", },
    { label: "mastodon", url: "./examples/mastodon.tutuca.tar.gz", },
    { label: "slack", url: "./examples/slack.tutuca.tar.gz", },
    { label: "table", url: "./examples/table.tutuca.tar.gz", },
    { label: "rust temp", url: "./examples/rust-tempconv.tutuca.tar.gz", },
    // The die `examples/dyncomp-dice` ships. It is offered here because its
    // own page cannot host it — that example builds against the PUBLISHED
    // package and imports one this repo added since — and a guest nothing can
    // run is a guest nothing notices going stale.
    { label: "dice", url: "./examples/dice.tutuca.tar.gz", },
  ]
}

// --- lifecycle exports ---------------------------------------------------

///|
pub fn mount() -> Unit {
  // The session is gated at BOTH ends by one option: restoring under `?test`
  // while saving always would mean an ordinary visit — which starts empty —
  // writing that empty page over the one somebody was working on.
  let session = if dev_mode {
    Some(@uiw.session_in_local_storage(prefix="tutuca-universal:"))
  } else {
    None
  }
  // The policy is `untrusted` plus the origins the sample bundles draw their
  // pictures from (`@shell.sample_policy`, which says why each one is on the
  // list). It applies to a DROPPED bundle as well, and that is the decision
  // being made here rather than a side effect: this page will let anything it
  // loads point an `<img src>` at those five hosts — never at an origin the
  // bundle picks, which is what the external-URL rule refuses.
  @uiw.mount(
    session~,
    samples=samples(),
    intents=@shell.sample_host_intents(),
    policy=@shell.sample_policy(),
  )
  |> ignore
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @uiw.on_event(ev)
}

///|
/// The JS bridge calls this once a dropped/fetched bundle is instantiated.
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @uiw.dyncomp_on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @uiw.dyncomp_on_load_error(load_id, msg)
}

///|
/// Recompile + reinject margaui CSS after a guest bundle registers new views
/// (and thus new utility classes). The loader calls it post-load.
pub fn refresh_margaui() -> Unit {
  @uiw.refresh_margaui()
}

///|
/// The app's whole state as JSON, for poking at the page from the console.
pub fn state_json() -> String {
  @uiw.state_json()
}
