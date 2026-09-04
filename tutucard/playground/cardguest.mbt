// --- mounting --------------------------------------------------------------

///|
/// What this page will accept from a compiled card.
///
/// `granted` rather than `untrusted`, and the difference is one thing: an
/// untrusted module may carry no `<style>` block, and most cards on this page
/// have one. That rule is right where it is — a host taking a module from
/// somewhere has no reason to let it write CSS — and wrong here, because the
/// module was compiled from the source in the editor two panes away. The reader
/// wrote it; there is nobody else to vouch.
///
/// What it does NOT widen is what the module can do, because that was settled
/// before this ran: a module's import section is its complete authority list,
/// so a card importing anything the runtime does not export is refused at
/// instantiation whatever this says.
fn card_policy() -> @policy.Policy {
  @policy.Policy::granted()
}

///|
/// The sentence inside a raised failure, without the machinery around it.
///
/// `fail` renders as `Failure(<file>:<line>@<pkg> FAILED: <what>)`, which is
/// right for a `moon test` line and wrong for a card author: the file it names
/// is the harness's, not theirs, and the only part they can act on is the tail.
fn why(e : Error) -> String {
  let s = e.to_string()
  let marker = "FAILED: "
  match s.find(marker) {
    Some(i) => {
      let rest = s[i + marker.length():].to_owned()
      // …and the closing paren `Failure(…)` wrapped it in.
      if rest.has_suffix(")") {
        rest[0:rest.length() - 1].to_owned()
      } else {
        rest
      }
    }
    None => s
  }
}

///|
fn mount_failed(msg : String) -> String {
  Json::object({ "ok": Json::boolean(false), "error": Json::string(msg) }).stringify()
}

///|
/// Register the instantiated card as a module and mount an instance
/// into the element with this id.
///
/// The page calls `loadGuest` first — that is what puts the module behind
/// `globalThis.__tgcmod` — and the manifest is read back off the module rather
/// than passed beside it. A manifest's field list is the order `get_field`
/// answers in, so one paired with a different module is a module whose halves
/// disagree; asking the module removes the pairing.
///
/// The instance is the app's ROOT rather than a child of some host component,
/// which is what `App::new` taking a value makes possible. There is nothing for
/// a wrapper to do here: the card is the whole of what this pane shows.
///
/// `init` names one of the component's `tutuca/fixtures` fixtures, and "" means
/// "whatever the card would show a visitor" — which is the fixture marked
/// `default` when there is one, and the schema's zero otherwise. A fixture is
/// the whole envelope rather than its field map: `value` seeds the instance,
/// `intents` answers what its steps ask the host, `drive` runs afterwards, and
/// `view` decides which of the component's views it is shown under.
///
/// Answers the same shape the other entry points do — `ok: false` with a reason
/// a person can act on, since every failure here is either the module being
/// refused or a manifest the host will not take.
pub fn mount_compiled(
  id : String,
  _manifest_json : String,
  init : String,
) -> String {
  // The same teardown-first order every mount here uses, and for the same
  // reason: the app holds transactor subscriptions and DOM listeners, and
  // pressing the button twice would otherwise leave the first set behind.
  teardown(id)
  guard @guest.native_ready(id) else {
    return mount_failed("no compiled card is instantiated on this page")
  }
  let doc = @dom.window().document()
  guard doc.getElementById(id) is Some(root_el) else {
    return mount_failed("there is no element with id '\{id}' to mount into")
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  root_node.replace_children()
  let scope = @component.ComponentStack::new()
  let slot = slot_of(id)
  let policy = card_policy()
  // The guest is built BEFORE it is registered and told about the module
  // afterwards, which is the only order available: `register_module` takes the
  // guest, and the guest needs the module to wrap a child token. Nothing can
  // call the guest in between.
  // Registration has one failure mode from a page's point of view — the module
  // was refused — and one thing worth showing: why. The reasons are a person's
  // to act on, so they reach the page rather than collapsing into a sentence
  // about mounting.
  let loaded = match @guest.register(id, scope, policy) {
    Ok(m) => m
    Err(reason) => return mount_failed(reason)
  }
  guard loaded.component_names() is [component, ..] else {
    return mount_failed("the manifest declares no component to mount")
  }
  // "" is not "no fixture": it is "nothing was named", and a card that marked
  // one has already said what to show then.
  let want = if init == "" { loaded.default_init(component) } else { init }
  let fixture = if want == "" {
    None
  } else {
    match @drive.fixture_of(loaded, component, want) {
      Some(f) => Some(f)
      // Named and missing, which is a different thing from unnamed. The
      // sentence is `tutucard/drive`'s, because a page and a scene reporting
      // the same miss two different ways is how a reader learns to distrust
      // one of them.
      None => {
        let names = loaded.init_names(component)
        return mount_failed(
          "no `tutuca/fixtures` fixture called `" +
          want +
          "` on `" +
          component +
          "`" +
          (if names.is_empty() {
            "; this component declares none"
          } else {
            " — it declares " + names.map(n => "`" + n + "`").join(", ")
          }),
        )
      }
    }
  }
  // The fixture's own intent answers FIRST, and the page's behind them.
  //
  // Both are offered in registration order, so this is the precedence rather
  // than a detail of it: a fixture that answers `rows` means its own three rows
  // rather than the page's, which is the same rule `tutucard/drive` follows one
  // level down when a scene and the fixture it starts from both answer a name.
  // A fixture that answers nothing gets the page's fixtures untouched, which is
  // every fixture that is not about asking a host for data.
  let (pre, answers) = match fixture {
    Some(f) => @drive.fixture_drive(f)
    None => ([], Map([]))
  }
  scope.register_intent_handlers(@drive.intent_handlers(answers))
  // …and the page's own behind them, in the scope OUTSIDE the module's. The
  // `lex` leg walks child -> parent, so a compiled card's `intent lex 'rows'`
  // is offered to its module's own handlers first — it registers none — and
  // then to these.
  scope.register_intent_handlers(playground_intents(slot, slot.gen))
  let made = match fixture {
    Some(f) => loaded.make_instance(component, args=f.args)
    None => loaded.make_instance(component)
  }
  guard made is Some(inst) else {
    return mount_failed("the guest would not create a '\{component}'")
  }
  // Which view to show it under. The one thing a value cannot say about
  // itself: a `Todo` has a `main` and a `row`, both over the same fields.
  let view = match fixture {
    Some(f) => f.view
    None => ""
  }
  let app = @app.App::new(
    scope,
    inst.to_value(),
    root_node,
    @bdom.opts_for(doc),
    view~,
  ) catch {
    _ => return mount_failed("the module's views did not compile into an app")
  }
  // The policy decides what a view may NAME; the same sanitizer makes the
  // render-time chain enforce it, so a policy is not half-applied by being
  // checked at registration and forgotten at render.
  app.set_sanitizer(policy.sanitizer)
  // Nothing to install here either. What a successor replaced is a thing
  // nothing holds, and what a removed row left behind is the same — both are
  // the engine's, now that the host holds instances rather than naming them.
  app.start()
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  // Into the same slot table `unmount` and `classesAt` read, which is what lets
  // those two work over this mount without knowing anything about it.
  slot.app = Some(app)
  // …and the activity panel, which reads what the transactor saw.
  app.transactor.observe(record => {
    slot.activity.push(record.to_json())
    if slot.activity.length() > ACTIVITY_CAP {
      slot.activity.remove(0) |> ignore
    }
  })
  |> ignore
  // tutuca has no lifecycle: the HOST dispatches `init`, exactly as it does for
  // the interpreted card in the pane beside this one.
  app.send_at_root("init") |> ignore
  // …and then the fixture's own steps, if it has any. AFTER `init`, because
  // they are what a person would have done to a card that had already loaded.
  //
  // The verbs are `testing/harness`'s, driving the BrowserNode this just
  // mounted — the same eight a `tutuca/test` scene uses against the in-memory
  // DOM. A step whose selector matched nothing is a fixture that cannot be
  // shown, so it fails the mount rather than leaving a half-driven card on the
  // page pretending to be the state it names.
  if !pre.is_empty() {
    @drive.seed(@harness.Harness::over(app, root_node), pre) catch {
      e => {
        // The element goes back to empty as well as the app going away: what is
        // on it is the card BEFORE the step that missed, and leaving that up
        // would be the pane showing a state the fixture does not name.
        teardown(id)
        root_node.replace_children()
        return mount_failed("fixture `\{want}`: \{why(e)}")
      }
    }
  }
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(component),
    "module": Json::string(loaded.module_name()),
    // A guest's views went through no build step, so these findings are the
    // only feedback its author gets.
    "diagnostics": Json::array(loaded.diagnostics().map(Json::string)),
  }).stringify()
}

///|
/// Drive the instantiated card's scenes, headless, and answer the report.
///
/// The other thing a compiled card is good for, and the one a page cannot do:
/// `mount_compiled` puts a card on a SCREEN, which proves it renders and
/// proves nothing about what it does when pressed. This mounts the same
/// module on the in-memory DOM instead, runs the block's steps through the
/// same transactor, and hands back the rendered HTML — so a card can be
/// checked by something with no page at all, which is what a build step and an
/// agent both are.
///
/// `scenes_json` overrides the card's own `<script type="tutuca/test">` block.
/// Empty means "use the block", and an override is what lets a card that
/// declares no tests be driven anyway — the case an agent is in when it has
/// just written one and wants to see what it does.
///
/// The manifest travels from the SAME compile the module came from, for the
/// reason `mount_compiled` gives: a manifest's field list is the order
/// `get-field` answers in, so one paired with a different module is a module
/// whose halves disagree.
pub fn drive(
  key : String,
  manifest_json : String,
  source : String,
  scenes_json : String,
) -> String {
  guard @guest.native_ready(key) else {
    return drive_failed("no compiled card is instantiated on this page")
  }
  let scenes = if scenes_json != "" {
    @scenedef.parse_scenes(scenes_json) catch {
      e => return drive_failed(e.message())
    }
  } else {
    let file = @viewfile.split_file(source, name="Card") catch {
      e => return drive_failed(e.message())
    }
    file.tests
  }
  let manifest = @host.DynManifest::from_json_string(manifest_json) catch {
    e => return drive_failed(e.message())
  }
  guard @guest.native_of(key) is Some(native) else {
    return drive_failed("no compiled card is instantiated on this page")
  }
  // What the HOST holds. It is the honest form of the question
  // `check-instances` asks: there is no table to count any more, and the tree
  // is what keeps an instance alive.
  //
  // A closure rather than a number, because `on_app` fires at MOUNT and the
  // question is about afterwards.
  let count : Ref[() -> Int] = { val: () => 0, }
  let report = @drive.run(
    native,
    manifest,
    scenes,
    on_bundle=b => @guest.adopt(key, native, b),
    on_app=a => {
      count.val = () => {
        let seen : Array[String] = []
        @host.live_instances(a.root_value(), seen)
        seen.length()
      }
    },
    take_log=() => @guest.take_log(key),
  )
  last_held.val = (count.val)()
  @drive.report_json(report).stringify()
}

///|
/// What the host held after the last drive.
let last_held : Ref[Int] = { val: 0, }

///|
/// …read from the page. `check-instances` is the only caller.
pub fn instance_count() -> Int {
  last_held.val
}

///|
/// A failure that stopped every scene, in the shape the report has — so a
/// caller reads one thing rather than two.
fn drive_failed(msg : String) -> String {
  Json::object({
    "ok": Json::boolean(false),
    "ran": Json::number(0),
    "failed": Json::number(0),
    "error": Json::string(msg),
    "scenes": Json::object({}),
  }).stringify()
}
