///| The universal dynamic-component host, built from nothing but the published
/// `marianoguerra/tutuca`.
///
/// Almost nothing is here, and that is the point. The editor is `dyncomp/ui`
/// (backend-agnostic) and the host around it is `dyncomp/ui/wasm` — both come
/// down with `moon add marianoguerra/tutuca`. What stays is the part that is
/// genuinely this page's: the one bundle it offers, the one service it lends,
/// and the wasm-gc export list.
///
/// An export list is per-package `link` configuration and cannot come from a
/// dependency, so the six entry points are re-exported below as one-line
/// forwards. That is the whole reason this is a package rather than a call.
///
/// Unlike the demo page upstream there is no `?test` gate and no session: this
/// page starts empty on every load, which is the honest default for something
/// you hand to someone, and it makes the walkthrough in README.md repeatable.

///|
fn main {

}

///|
/// The one bundle this page ships with — `../dice`, built and packed beside it
/// by `../build.mjs`. It is offered as a button; dropping any other
/// `.tutuca.tar.gz` on the page works too, and needs no entry here.
fn samples() -> Array[@shell.LoaderBarSample] {
  [{ label: "dice (built here)", url: "./examples/dice.tutuca.tar.gz" }]
}

// --- the one service this host lends -------------------------------------

///|
/// xorshift32. Not for anything that matters — it is a die.
///
/// A die needs a number nobody can predict, and a `tutuca:component` guest
/// cannot make one: its world imports no WASI, so there is no clock and no
/// entropy in there at all.
///
/// So the die asks through `control.intent`, which is not ambient authority —
/// it is one question, answered once, by a page that could decline. That is
/// the interesting seam anyway: the guest and the host holding a
/// conversation.
let seed : Ref[UInt] = { val: 0x9E3779B9 }

///|
/// Seeded from `Date.now()` as a STRING. The clock is reachable through
/// `mizchi/js/core` — `_call` is `call0` in the loader's `jscore` shim — but
/// an externref carrying a JS number has no cheap route to a MoonBit `Double`
/// on wasm-gc, and folding the decimal digits is enough to make two page loads
/// disagree.
fn seed_from_clock() -> Unit {
  let date = @core.global_this()._get("Date")
  if @core.is_nullish(date) {
    return
  }
  let now = date._call("now", [])
  if @core.is_nullish(now) {
    return
  }
  let mut s : UInt = 0x9E3779B9
  for c in now.to_string() {
    s = s * 31 + c.to_uint()
  }
  // 0 is xorshift's fixed point: it would give the same face forever.
  seed.val = if s == 0 { 0x9E3779B9 } else { s }
}

///|
fn next_u32() -> UInt {
  let mut x = seed.val
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  seed.val = x
  x
}

///|
/// Services this HOST provides to whatever it hosts.
///
/// `roll` is what the die calls (the `roll` intent in
/// `../dice/gen/interface/tutuca/component/guest/dice.mbt`). The `println` is
/// deliberate: it lowers to a `console.log` import, so a line in the browser
/// console is proof that a sandboxed guest reached this map — which is the
/// single thing this example exists to demonstrate.
///
/// A bundle that serves a name of its own answers its components first; this is
/// only reached because the die's bundle serves nothing.
///
/// **The v2 shape.** Tutuca's four dispatch channels became two, and a
/// request is an intent on the `lex` leg — so what a host registers is an
/// `IntentFn` and a LIST of them per name, because the leg walks: a handler
/// that answers `Pass` declines and the next one is tried.
///
/// One answer is worth having here. A handler that MUST respond cannot decline, so a
/// handler with nothing to contribute could only invent an error; this one
/// could answer `Pass` and let the route run out, and the page would hear
/// `rollUnhandled` — "nothing on this page rolls dice", which is a different
/// sentence from "the roll failed".
fn host_intents() -> Map[String, Array[@component.IntentFn]] {
  {
    "roll": [
      IntentFn((call, answer) => match call.args {
        [Num(faces)] => {
          let n = faces.to_int()
          if n < 2 {
            answer(Failed(Str("roll: a die needs at least two faces")))
          } else {
            let face = (next_u32() % n.reinterpret_as_uint()).reinterpret_as_int() +
              1
            println("host: rolled \{face} on a d\{n}")
            answer(Ok(Num(face.to_double())))
          }
        }
        _ => answer(Failed(Str("roll: expected one number (the face count)")))
      }),
    ],
  }
}

// --- lifecycle exports ---------------------------------------------------

///|
/// `policy` is passed even though `untrusted` is what it already defaults to.
///
/// Partly because it is the decision a host page most owes an answer to, and a
/// stated one reads as a choice rather than an oversight — this page accepts a
/// bundle from anywhere, so it allows it nothing: no external URLs and no
/// stylesheet of its own. `@policy.Policy::granted()` is the line to change,
/// and it means a person said yes.
///
/// Partly because an argument nobody passes is an argument nobody notices is
/// missing. Until 0.9.6 there was no `policy` here to pass: `dyncomp/ui/wasm`
/// registered every bundle as untrusted and gave a page no say, so the two
/// upper tiers were reachable only from a test. This example is what found
/// that, and writing the argument out is what makes the next such gap a build
/// error here rather than something somebody has to go looking for.
pub fn mount() -> Unit {
  seed_from_clock()
  @uiw.mount(
    samples=samples(),
    intents=host_intents(),
    policy=@policy.Policy::untrusted(),
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
