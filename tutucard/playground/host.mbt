// The card playground's host.
//
// One function does the work: `load(source)` parses a card, mounts it, and
// answers what was wrong with it. The page calls that on every keystroke, and
// there is no compiler, no worker and no build step between the two.

///|
/// The mounted app, held so the panels can read it after events have morphed
/// the DOM, and so the next `load` can tear it down.
let current : Ref[@app.App[@bdom.BrowserNode]?] = Ref(None)

///|
/// Where the card mounts. One app per page, which is the playground shape.
let root_id : Ref[String] = Ref("preview")

///|
/// How many dispatches the activity panel keeps. A bound, not a budget: the
/// page polls after every interaction, and a long session would otherwise grow
/// a log nobody scrolls back through.
const ACTIVITY_CAP = 200

///|
let activity : Array[Json] = []

///|
/// Install the page-facing entry points.
///
/// `load` is the whole API. Everything else is a getter the panels poll, in
/// the same shape `playground/host` publishes — so the shell's inspector,
/// activity and margaui panes work over a card without knowing it is one.
pub fn install() -> Unit {
  publish(
    (source, name) => load(source, name),
    (source, name) => check(source, name),
    () => state_json(),
    () => classes_json(),
    () => activity_json(),
  )
}

///|
extern "js" fn publish(
  load : (String, String) -> String,
  check : (String, String) -> String,
  state : () -> String,
  classes : () -> String,
  activity : () -> String,
) -> Unit =
  #|(load, check, state, classes, activity) => { globalThis.__tutucard = { load, check, state, classes, activity } }

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
  teardown()
  report(source, name, mount_it=true)
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
  report(source, name, mount_it=false)
}

///|
fn report(source : String, name : String, mount_it~ : Bool) -> String {
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
  let mounted = if mount_it { mount(card) } else { false }
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
fn teardown() -> Unit {
  match current.val {
    Some(app) => app.destroy()
    None => ()
  }
  current.val = None
  activity.clear()
}

///|
fn mount(card : @tutucard.Card) -> Bool {
  let doc = @dom.window().document()
  guard doc.getElementById(root_id.val) is Some(root_el) else { return false }
  // The preview element is reused across loads, so whatever the last card
  // rendered has to go before this one renders into it.
  let root_node = @bdom.BrowserNode::from_element(root_el)
  root_node.replace_children()
  let m = @component.ModuleDef::new(name="card", components=[card.component])
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
  @glue.install_styles(a, @bdom.BrowserNode::from_document(doc))
  current.val = Some(a)
  a.transactor.observe(record => {
    activity.push(record.to_json())
    if activity.length() > ACTIVITY_CAP {
      activity.remove(0) |> ignore
    }
  })
  |> ignore
  // tutuca has no lifecycle: the HOST dispatches `init`, so a card with a
  // `receive init` arm gets one exactly as a compiled component does.
  a.send_at_root("init") |> ignore
  true
}

///|
/// The dispatches since the last load, as a JSON array.
pub fn activity_json() -> String {
  Json::array(activity).stringify()
}

///|
/// The card's current state, as JSON — an instance projects to its declared
/// fields, so the panel shows the state tree.
pub fn state_json() -> String {
  match current.val {
    Some(a) => a.root_value().to_json().stringify()
    None => "null"
  }
}

///|
/// The margaui class set the mounted views can show, for the page to compile.
pub fn classes_json() -> String {
  match current.val {
    Some(a) => {
      let arr = a.scope.comps.collect_classes()
      Json::array(arr.map(c => Json::string(c))).stringify()
    }
    None => "[]"
  }
}
