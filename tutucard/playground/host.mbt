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
      let s = Slot::{ app: None, activity: [] }
      slots[id] = s
      s
    }
  }
}

///|
/// Install the page-facing entry points.
///
/// `load` is the whole API for the playground page. Everything else is a
/// getter the panels poll, in the same shape `playground/host` publishes — so
/// the shell's inspector and activity panels work over a card without knowing
/// it is one, and `classes` feeds the same margaui compiler the other
/// playground hands `__tutuca.classes()` to.
///
/// `mount` / `unmount` are the same loop addressed by mount point rather than
/// by "the page's one card", which is what an embedded example needs: it
/// arrives and leaves with its element, and several live side by side. So is
/// `classesAt`: an embedded card is styled where it sits, and the page's one
/// card is not a thing it can ask about.
pub fn install() -> Unit {
  publish(
    (source, name) => load(source, name),
    (source, name) => check(source, name),
    () => state_json(),
    () => classes_json(),
    () => activity_json(),
    (id, source, name) => mount_at(id, source, name),
    id => unmount_at(id),
    id => classes_at(id),
  )
}

///|
extern "js" fn publish(
  load : (String, String) -> String,
  check : (String, String) -> String,
  state : () -> String,
  classes : () -> String,
  activity : () -> String,
  mount : (String, String, String) -> String,
  unmount : (String) -> Unit,
  classes_at : (String) -> String,
) -> Unit =
  #|(load, check, state, classes, activity, mount, unmount, classesAt) => { globalThis.__tutucard = { load, check, state, classes, activity, mount, unmount, classesAt } }

///|
/// Parse, check and mount a card into the element with this id.
///
/// The same report `load` answers, and the same teardown-first order — the
/// difference is only WHERE, which is the whole of what an embed needs. An id
/// that is not on the page answers `"mounted": false` rather than failing:
/// an embed that has been removed while a debounce was in flight is an
/// ordinary thing, not an error to report to a reader.
pub fn mount_at(id : String, source : String, name : String) -> String {
  teardown(id)
  report(source, name, mount_into=Some(id))
}

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
/// Parse, check and mount a card. Answers a JSON report the editor reads.
///
/// ```json
/// { "ok": true,  "component": "Counter", "issues": [ … ] }
/// { "ok": false, "error": "line 4: expected a value, found `}`", "line": 4,
///   "start": 118, "end": 119 }
/// ```
///
/// `ok: false` means there is nothing to mount — the file does not split, or
/// the script does not parse. `ok: true` with a non-empty `issues` is the
/// ordinary state of a card being edited: it renders, and the things wrong
/// with it are listed. Refusing to show anything until everything is right is
/// what makes a live editor unusable, and a live editor is the one thing this
/// exists to be good at.
pub fn load(source : String, name : String) -> String {
  mount_at(root_id.val, source, name)
}

///|
/// Parse and check a card WITHOUT mounting it.
///
/// The same report, minus the part that needs a page. Worth being a separate
/// entry rather than a flag: validating a card is a thing a host does without
/// showing one — an agent that generated it, a build step over a directory of
/// them, or the check that keeps the starter cards on this page loading — and
/// none of those has a DOM.
pub fn check(source : String, name : String) -> String {
  report(source, name, mount_into=None)
}

///|
fn report(source : String, name : String, mount_into~ : String?) -> String {
  let card = @tutucard.load(source, name~) catch {
    e => {
      let (line, from, to) = locate(e)
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(e.message()),
        "line": Json::number(line.to_double()),
        "start": Json::number(from.to_double()),
        "end": Json::number(to.to_double()),
      }).stringify()
    }
  }
  let issues = card.issues.map(i => {
    Json::object({
      "code": Json::string(i.code),
      "message": Json::string(i.message),
      "line": Json::number(i.line.to_double()),
      "start": Json::number(i.span.start.to_double()),
      "end": Json::number(i.span.end_.to_double()),
    })
  })
  let mounted = match mount_into {
    Some(id) => mount(card, id)
    None => false
  }
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(card.component.name),
    "mounted": Json::boolean(mounted),
    "issues": Json::array(issues),
  }).stringify()
}

///|
/// Where a load failure happened. A file failure has no span of its own — it
/// is about the file's structure rather than a position in it — so it reports
/// the whole of it and lets the editor decide what to highlight.
fn locate(e : @tutucard.CardError) -> (Int, Int, Int) {
  match e {
    BadScript(line~, span~, ..) => (line, span.start, span.end_)
    _ => (1, 0, 0)
  }
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
}

///|
fn mount(card : @tutucard.Card, id : String) -> Bool {
  let doc = @dom.window().document()
  guard doc.getElementById(id) is Some(root_el) else { return false }
  // The preview element is reused across loads, so whatever the last card
  // rendered has to go before this one renders into it.
  let root_node = @bdom.BrowserNode::from_element(root_el)
  root_node.replace_children()
  // The file's macros travel with it: `<x:name>` in a card expands against the
  // scope the module registers, exactly as a generated module's does.
  let m = @component.ModuleDef::new(
    name="card",
    components=[card.component],
    macros=card.macros,
  )
  let a = @app.App::from_module(
    m,
    card.component.name,
    root_node,
    @bdom.opts_for(doc),
    args=card.initial(),
  ) catch {
    _ => return false
  }
  @glue.install(a)
  // Into the DOCUMENT, not the mount point: a card's `<style>` blocks are
  // scoped by the framework, so several embedded cards on one page each add
  // their own rules without reaching each other's nodes.
  @glue.install_styles(a, @bdom.BrowserNode::from_document(doc))
  let slot = slot_of(id)
  slot.app = Some(a)
  a.transactor.observe(record => {
    slot.activity.push(record.to_json())
    if slot.activity.length() > ACTIVITY_CAP {
      slot.activity.remove(0) |> ignore
    }
  })
  |> ignore
  // tutuca has no lifecycle: the HOST dispatches `init`, so a card with a
  // `receive init` arm gets one exactly as a compiled component does.
  a.send_at_root("init") |> ignore
  true
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
