// The card playground's host.
//
// One function does the work: `load(source)` parses a card, mounts it, and
// answers what was wrong with it. The page calls that on every keystroke, and
// there is no compiler, no worker and no build step between the two.

///|
/// One mounted card: the app, and the dispatches it has raised since it was
/// mounted.
///
/// The app is held so the panels can read it after events have morphed the
/// DOM, and so the next load into the same place can tear it down.
priv struct Slot {
  mut app : @app.App[@bdom.BrowserNode]?
  activity : Array[Json]
  /// Bumped by every teardown of this mount point.
  ///
  /// The fixtures answer LATE, and a card is remounted on every keystroke, so
  /// a timer outlives the app that asked. The generation the handler captured
  /// is what tells a late answer from a live one — per slot rather than
  /// global, because an embedded card mounting elsewhere says nothing about
  /// whether this one is still there.
  mut gen : Int
}

///|
/// The mounted cards, by the id of the element each renders into.
///
/// A Map rather than one `current`, because a card is now two things: the
/// playground page, which has exactly one, and an embedded example, of which a
/// page of documentation has as many as it has examples. Keying by the mount
/// point is what makes the second work — the element is where a card lives,
/// and two cards cannot share one.
let slots : Map[String, Slot] = Map([])

///|
/// Where the playground page's card mounts. The embeds pass their own.
let root_id : Ref[String] = Ref("preview")

///|
/// How many dispatches the activity panel keeps. A bound, not a budget: the
/// page polls after every interaction, and a long session would otherwise grow
/// a log nobody scrolls back through.
const ACTIVITY_CAP = 200

///|
/// The slot for a mount point, made on first use.
fn slot_of(id : String) -> Slot {
  match slots.get(id) {
    Some(s) => s
    None => {
      let s = Slot::{ app: None, activity: [], gen: 0, }
      slots[id] = s
      s
    }
  }
}

///|
/// Install the page-facing entry points.
///
/// `check` is the whole API for validating a card. Everything else is a getter
/// the panels poll, in the same shape `playground/host` publishes — so the
/// shell's inspector and activity panels work over a card without knowing it is
/// one, and `classes` feeds the same margaui compiler the other playground
/// hands `__tutuca.classes()` to.
///
/// `unmount` and `classesAt` are addressed by MOUNT POINT rather than by "the
/// page's one card", which is what an embedded example needs: it arrives and
/// leaves with its element, and several live side by side.
///
/// `drive` is the other thing to do with a compiled card, and the one no page
/// is needed for: `mountCompiled` puts it on a screen, which proves it renders
/// and proves nothing about what it does when pressed. `drive` mounts the same
/// bundle on the IN-MEMORY DOM, runs the card's `<script type="tutuca/test">`
/// scenes through the same transactor, and answers the rendered HTML — so the
/// same bundle that serves this page also answers to `node`, which is what a
/// build step and an agent both are.
///
/// `resetSweep` is the one entry point a PAGE never calls: `card-wasm.js` calls
/// it when it installs a new instance table under a key, because the collector
/// records what each app on that key could reach and those records are handles
/// into the table that just went away.
///
/// `compile` and `mountCompiled` are the two halves of showing a card: a card
/// is mounted by compiling it and instantiating the module. Instantiation is
/// `WebAssembly`, which answers a promise, so the sequence lives in
/// `web/card-wasm.js` as `mountCard` — the one thing on this boundary that
/// could not be a synchronous MoonBit call.
pub fn install() -> Unit {
  publish(
    (source, name) => check(source, name),
    (source, name, allow_wax) => compile(source, name, allow_wax),
    () => state_json(),
    () => classes_json(),
    () => activity_json(),
    id => unmount_at(id),
    id => classes_at(id),
    (id, manifest, init) => mount_compiled(id, manifest, init),
    (key, manifest, source, scenes) => drive(key, manifest, source, scenes),
    key => forget_sweep_roots(key),
    (source, name) => compile_tgc(source, name),
    () => runtime_wasm(),
  )
}

///|
/// The same card, through the OTHER backend.
///
/// `tgc/emit` compiles to a core wasm module using the GC proposal and nothing
/// else — no component model, no WIT, no archive, no linear memory — and the
/// module carries its own manifest, so what comes back here is one file rather
/// than a file plus a sidecar. See `tgc/SPEC.md`.
///
/// It is beside `compile` rather than replacing it while the host half is being
/// built: this page can already GENERATE and DOWNLOAD a `tgc` module, and
/// mounting one goes through `tgcguest.mbt`.
pub fn compile_tgc(source : String, name : String) -> String {
  let out = @tgc.compile(source, name~) catch {
    e =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(e.message()),
      }).stringify()
  }
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(out.component),
    "components": Json::array(out.components.map(Json::string)),
    "wasm": Json::string(@base64.encode(out.wasm)),
    "size": Json::number(out.wasm.length().to_double()),
    "wax": Json::string(out.wax),
    "manifest": out.manifest,
    "fields": Json::array(out.fields.map(Json::string)),
    "refusals": Json::array(
      out.refusals.map(r => {
        Json::object({
          "kind": Json::string(r.kind),
          "name": Json::string(r.name),
          "reason": Json::string(r.reason),
          "line": Json::number(r.line.to_double()),
        })
      }),
    ),
  }).stringify()
}

///|
/// The runtime module, base64.
///
/// One per page rather than one per card: `tut` is shared, which is the point
/// of it. The page caches what this answers.
pub fn runtime_wasm() -> String {
  let bytes = @tgc.compile_runtime() catch {
    e =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(e.message()),
      }).stringify()
  }
  Json::object({
    "ok": Json::boolean(true),
    "wasm": Json::string(@base64.encode(bytes)),
    "size": Json::number(bytes.length().to_double()),
  }).stringify()
}

///|
extern "js" fn publish(
  check : (String, String) -> String,
  compile : (String, String, Bool) -> String,
  state : () -> String,
  classes : () -> String,
  activity : () -> String,
  unmount : (String) -> Unit,
  classes_at : (String) -> String,
  mount_compiled : (String, String, String) -> String,
  drive : (String, String, String, String) -> String,
  reset_sweep : (String) -> Unit,
  compile_tgc : (String, String) -> String,
  runtime_wasm : () -> String,
) -> Unit =
  #|(check, compile, state, classes, activity, unmount, classesAt, mountCompiled, drive, resetSweep, compileTgc, runtimeWasm) => { globalThis.__tutucard = { check, compile, state, classes, activity, unmount, classesAt, mountCompiled, drive, resetSweep, compileTgc, runtimeWasm } }

///|
/// Tear a card down and forget its mount point.
///
/// Called when an embed leaves the document. Dropping the slot as well as the
/// app matters: the map is keyed by element id, and a page that adds and
/// removes embeds would otherwise keep one entry per id it has ever used.
pub fn unmount_at(id : String) -> Unit {
  teardown(id)
  slots.remove(id)
}

///|
/// Parse and check a card WITHOUT mounting it. Answers a JSON report.
///
/// ```json
/// { "ok": true,  "component": "Counter", "issues": [ … ] }
/// { "ok": false, "error": "line 4: expected a value, found `}`", "line": 4,
///   "start": 118, "end": 119 }
/// ```
///
/// `ok: false` means there is nothing to mount — the file does not split, or
/// the script does not parse. `ok: true` with a non-empty `issues` is the
/// ordinary state of a card being edited: it renders, and the things wrong with
/// it are listed. Refusing to show anything until everything is right is what
/// makes a live editor unusable, and a live editor is the one thing this exists
/// to be good at.
///
/// MOUNTING is not here any more, and cannot be: a card is mounted by compiling
/// it and instantiating the module, and instantiation is `WebAssembly` — which
/// answers a promise. So the three steps live in `web/card-wasm.js` as
/// `mountCard`, and what is left on this side is the half that needs no page
/// (`check`) and the half that needs a module already running (`mountCompiled`).
pub fn check(source : String, name : String) -> String {
  let out = @wasm.check_card(source, name~) catch {
    e =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(e.message()),
        // A whole-card failure is about the file's structure rather than a
        // position in it, so the editor decides what to highlight.
        "line": Json::number(1),
        "start": Json::number(0),
        "end": Json::number(0),
      }).stringify()
  }
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(out.component),
    "issues": Json::array(
      out.issues.map(i => {
        Json::object({
          "code": Json::string(i.code),
          "message": Json::string(i.message),
          "line": Json::number(i.line.to_double()),
          "start": Json::number(i.span.start.to_double()),
          "end": Json::number(i.span.end_.to_double()),
        })
      }),
    ),
  }).stringify()
}

///|
/// Tear the mounted app down.
///
/// Called before every load, and it has to be: the app holds transactor
/// subscriptions and DOM listeners, and a keystroke-driven editor would
/// otherwise accumulate one set per character typed.
fn teardown(id : String) -> Unit {
  guard slots.get(id) is Some(slot) else { return }
  match slot.app {
    Some(app) => app.destroy()
    None => ()
  }
  slot.app = None
  slot.activity.clear()
  // …and what the sweep for this mount point was walking. The apps that
  // registered those roots are gone, and the next mount installs its own.
  forget_sweep_roots(id)
  // Whatever this card asked the host for, it is no longer here to be told.
  slot.gen += 1
}

///|
/// `setTimeout`, for the one thing the fixtures below need that the runtime
/// deliberately has none of: a clock.
extern "js" fn set_timeout(cb : () -> Unit, ms : Int) -> Unit =
  #|(cb, ms) => { setTimeout(cb, ms) }

///|
/// The intents this page answers, for every card it mounts.
///
/// Three fixtures, and they are fixtures rather than an API: a card names a
/// JOB and the host decides what that name means, so what a page registers is
/// the page's business. This one is a playground, so what it can honestly
/// offer is canned data — `rows` answers a list, `echo` answers the first
/// thing it was handed, and `fail` fails. A card that wants a real fetch
/// belongs in a page that has one.
///
/// **A name that is not here answers nothing at all**, and that is the point
/// rather than a gap: the `lex` leg runs out, nobody claimed the intent, and
/// the card hears `<name>Unhandled` — which is a different sentence from
/// `fail`'s, and the one a must-answer handler could not say. Registering these takes
/// nothing away from a card demonstrating that path; it is what makes the
/// contrast visible on one page.
///
/// A list per name, because the leg WALKS: a handler that answers `Pass`
/// declines and the next one is tried. One each here, and the shape is the
/// point — a scope can hold several.
///
/// They answer LATE, and that is the point rather than a simulation detail: an
/// answer that lands before the transaction finishes never shows a card its
/// own loading state, which is the half of asynchrony a card author has to
/// write for. `gen` is the mount they were built for; a card that has been
/// torn down since gets no answer, because there is nobody left to tell.
fn playground_intents(
  slot : Slot,
  gen : Int,
) -> Map[String, Array[@component.IntentFn]] {
  fn later(ms : Int, f : () -> Unit) -> Unit {
    set_timeout(() => if slot.gen == gen { f() }, ms)
  }

  {
    "rows": [
      @tutuca.IntentFn((_call, answer) => {
        later(500, () => {
          answer(
            Ok(
              @tutuca.Value::List([
                Map({
                  "title": Str("Tutuca"),
                  "description": Str("A SPA framework that fits in your head"),
                }),
                Map({
                  "title": Str("MoonBit"),
                  "description": Str("The language this port is written in"),
                }),
                Map({
                  "title": Str("Borges"),
                  "description": Str(
                    "Wrote the list the other examples iterate",
                  ),
                }),
              ]),
            ),
          )
        })
      }),
    ],
    "echo": [
      @tutuca.IntentFn((call, answer) => {
        later(300, () => answer(Ok(call.args.get(0).unwrap_or(Null))))
      }),
    ],
    "fail": [
      @tutuca.IntentFn((_call, answer) => {
        later(500, () => answer(Failed(Str("the host said no"))))
      }),
    ],
  }
}

///|
/// The dispatches since the playground page's card was last loaded, as a JSON
/// array.
pub fn activity_json() -> String {
  match slots.get(root_id.val) {
    Some(slot) => Json::array(slot.activity).stringify()
    None => "[]"
  }
}

///|
/// The playground page's card's current state, as JSON — an instance projects
/// to its declared fields, so the panel shows the state tree.
pub fn state_json() -> String {
  match page_app() {
    Some(a) => a.root_value().to_json().stringify()
    None => "null"
  }
}

///|
/// The app the playground page's panels read. The embeds have their own and
/// show no panels, so this is the only slot the getters ever ask about.
fn page_app() -> @app.App[@bdom.BrowserNode]? {
  match slots.get(root_id.val) {
    Some(slot) => slot.app
    None => None
  }
}

///|
/// The margaui class set the playground page's card can show, for the page to
/// compile.
pub fn classes_json() -> String {
  classes_of(page_app())
}

///|
/// The same, for the card mounted at one element.
///
/// The class set is a property of a MOUNTED card, not of its source: a class
/// name reaches it through a `:class` binding as easily as through a literal,
/// and only the built views know which. So this is asked after the mount that
/// produced it, exactly as `state` and `activity` are.
pub fn classes_at(id : String) -> String {
  classes_of(
    match slots.get(id) {
      Some(slot) => slot.app
      None => None
    },
  )
}

///|
fn classes_of(app : @app.App[@bdom.BrowserNode]?) -> String {
  match app {
    Some(a) => {
      let arr = a.scope.comps.collect_classes()
      Json::array(arr.map(c => Json::string(c))).stringify()
    }
    None => "[]"
  }
}

// ---------------------------------------------------------------------------
// the compiler

///|
/// Compile a card to a `tutuca:component@0.12.0` core wasm module.
///
/// The same card the page is already interpreting, put through the OTHER
/// backend — so the two answers sit side by side and a difference between them
/// is visible rather than theoretical. `tutucard/wasm` does the work; this only
/// shapes it for a page.
///
/// The wasm crosses as base64 because a MoonBit extern cannot hand JavaScript a
/// byte array, and the page has to hold the real bytes: it instantiates them
/// through `abi.mjs` and packs them into the archive the download button hands
/// you.
pub fn compile(source : String, name : String, allow_wax : Bool) -> String {
  let out = @wasm.compile(source, name~, allow_wax~) catch {
    e =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(e.message()),
      }).stringify()
  }
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(out.component),
    "wasm": Json::string(@base64.encode(out.wasm)),
    "size": Json::number(out.wasm.length().to_double()),
    "wax": Json::string(out.wax),
    "wat": Json::string(out.wat),
    "manifest": out.manifest,
    "descriptor": out.descriptor,
    "fields": Json::array(out.fields.map(Json::string)),
    "refusals": Json::array(
      out.refusals.map(r => {
        Json::object({
          "kind": Json::string(r.kind),
          "name": Json::string(r.name),
          "reason": Json::string(r.reason),
          "line": Json::number(r.line.to_double()),
        })
      }),
    ),
    // The other half of the refusal panel: what the card ANSWERED in Wax, and
    // for a name it also declared, the reason the block language turned it
    // away. A refusal and the escape that answers it are one story.
    "escapes": Json::array(
      out.escapes.map(e => {
        Json::object({
          "kind": Json::string(e.kind),
          "name": Json::string(e.name),
          "fn": Json::string(e.fn_name),
          "declared": Json::boolean(e.declared),
          "replaced": Json::string(e.replaced),
        })
      }),
    ),
  }).stringify()
}
