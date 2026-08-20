///| Blackbox tests: mount a guest bundle (via an in-process FakeGuest) into
/// a live app on memdom and drive it through the stock pipeline — render
/// reads fields lazily, clicks dispatch through the synthesized component's
/// compiled views, successors re-render, control messages drain via &Ctx,
/// requests round-trip, nested guest children dispatch through two DynObj
/// levels, and superseded guest handles are collected.

///|
priv struct FakeGuest {
  counters : Map[Int, Double]
  /// every value this counter has held, so a view can `@each` over it with a
  /// `@when` filter the GUEST answers
  histories : Map[Int, Array[Double]]
  pairs : Map[Int, (Int, Int)]
  /// `Framed` instances, by handle. Its OTHER field — the placeholder — is not
  /// here and cannot be: the guest never sees what fills it.
  titles : Map[Int, String]
  next : Ref[Int]
  bundle : Ref[Bundle?]
  /// requests the bundle served, in order (the guest-served request test)
  served : Array[String]
}

///|
fn FakeGuest::new() -> FakeGuest {
  {
    counters: Map([]),
    histories: Map([]),
    pairs: Map([]),
    titles: Map([]),
    next: { val: 0 },
    bundle: { val: None },
    served: [],
  }
}

///|
fn FakeGuest::alloc(
  self : FakeGuest,
  count : Double,
  history? : Array[Double] = [],
) -> Int {
  let h = self.next.val
  self.next.val = h + 1
  self.counters[h] = count
  self.histories[h] = history
  h
}

///|
/// A successor of `handle` at `count`, keeping the history and appending the
/// value being left behind (mirrors the real counter guest).
fn FakeGuest::next_of(self : FakeGuest, handle : Int, count : Double) -> Int {
  let history = self.histories.get(handle).unwrap_or([]).copy()
  history.push(self.counters.get(handle).unwrap())
  self.alloc(count, history~)
}

///|
fn FakeGuest::alloc_pair(self : FakeGuest, left : Int, right : Int) -> Int {
  let h = self.next.val
  self.next.val = h + 1
  self.pairs[h] = (left, right)
  h
}

///|
fn FakeGuest::wrap_child(self : FakeGuest, handle : Int) -> @tutuca.Value {
  // mirrors the wasm bridge: resolve through the registered bundle
  self.bundle.val.unwrap().wrap_instance("Counter", handle).unwrap()
}

///|
fn child_handle(v : @tutuca.Value) -> Int? {
  match v {
    Obj(o) =>
      match o.obj_field(handle_field) {
        Some(Num(n)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
impl Guest for FakeGuest with fn create(self, component, args) {
  match component {
    "Pair" => self.alloc_pair(self.alloc(1.0), self.alloc(100.0))
    "Framed" => {
      let h = self.next.val
      self.next.val = h + 1
      self.titles[h] = match args.get("title") {
        Some(Str(t)) => t
        _ => "untitled"
      }
      h
    }
    _ => {
      let count = match args.get("count") {
        Some(Num(n)) => n
        _ => 0.0
      }
      self.alloc(count)
    }
  }
}

///|
impl Guest for FakeGuest with fn get_field(self, handle, name) {
  // A Framed answers its title and nothing else. Asked for `body` it says
  // None — which it never is, because the host answers that one itself.
  if self.titles.get(handle) is Some(title) {
    return if name == "title" { Some(Str(title)) } else { None }
  }
  match self.pairs.get(handle) {
    Some((l, r)) =>
      match name {
        "left" => Some(self.wrap_child(l))
        "right" => Some(self.wrap_child(r))
        _ => None
      }
    None =>
      match name {
        "count" => Some(Num(self.counters.get(handle).unwrap()))
        "history" =>
          Some(
            List(
              self.histories
              .get(handle)
              .unwrap_or([])
              .map(n => (Num(n) : @tutuca.Value)),
            ),
          )
        _ => None
      }
  }
}

///|
impl Guest for FakeGuest with fn dispatch(self, handle, bucket, name, args) {
  // the Pair's own buckets: it answers its children's intents and addresses
  // them by relative path
  if self.pairs.get(handle) is Some((l, r)) {
    return match (bucket, name) {
      // a child announced itself: swap the two, and end the walk so the intent
      // does not reach the host shell above
      (Intent, "counted") =>
        {
          handled: true,
          next: Some(self.alloc_pair(r, l)),
          msgs: [StopPropagation],
        }
      // reach INTO the subtree: `.left` is the child the left field holds
      (Receive, "resetLeft") =>
        {
          handled: true,
          next: None,
          msgs: [SendAt([FieldStep("left")], "setTo", [Num(0)])],
        }
      _ => { handled: false, next: None, msgs: [] }
    }
  }
  if self.titles.contains(handle) {
    return { handled: false, next: None, msgs: [] }
  }
  let count = self.counters.get(handle).unwrap()
  match (bucket, name) {
    (Receive, "inc") =>
      { handled: true, next: Some(self.next_of(handle, count + 1.0)), msgs: [] }
    (Receive, "dec") =>
      { handled: true, next: Some(self.next_of(handle, count - 1.0)), msgs: [] }
    // the answer comes back at "doubled" with just the value (on_ok_name)
    (Receive, "double") =>
      {
        handled: true,
        next: None,
        msgs: [
          Intent(
            "double",
            [Num(count)],
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="doubled"),
          ),
        ],
      }
    (Receive, "doubled") =>
      match args {
        [Num(n), ..] =>
          { handled: true, next: Some(self.next_of(handle, n)), msgs: [] }
        _ => { handled: true, next: None, msgs: [] }
      }
    // an intent the BUNDLE serves on its own scope (see serve_intent), not
    // one the host answers
    (Receive, "triple") =>
      {
        handled: true,
        next: None,
        msgs: [
          Intent(
            "triple",
            [Num(count)],
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="tripled"),
          ),
        ],
      }
    (Receive, "tripled") =>
      match args {
        [Num(n), ..] =>
          { handled: true, next: Some(self.next_of(handle, n)), msgs: [] }
        _ => { handled: true, next: None, msgs: [] }
      }
    (Receive, "notify") =>
      {
        handled: true,
        next: None,
        msgs: [
          Intent(
            "counterChanged",
            [Str("changed!")],
            @tutuca.IntentOpts::new(route=[Dyn]),
          ),
        ],
      }
    // walks up to whatever is above: a Pair parent, or the host shell
    (Receive, "announce") =>
      {
        handled: true,
        next: None,
        msgs: [
          Intent("counted", [Num(count)], @tutuca.IntentOpts::new(route=[Dyn])),
        ],
      }
    (Receive, "reset") =>
      { handled: true, next: Some(self.next_of(handle, 0.0)), msgs: [] }
    (Receive, "setTo") =>
      match args {
        [Num(n), ..] =>
          { handled: true, next: Some(self.next_of(handle, n)), msgs: [] }
        _ => { handled: true, next: None, msgs: [] }
      }
    _ => { handled: false, next: None, msgs: [] }
  }
}

///|
/// The bundle's own service: its components reach it before the host's.
impl Guest for FakeGuest with fn serve_intent(self, name, args) {
  self.served.push(name)
  match (name, args) {
    ("triple", [Num(n), ..]) => Ok(Num(n * 3.0))
    _ => Err(Str("no such service: \{name}"))
  }
}

///|
impl Guest for FakeGuest with fn call_method(self, handle, name, args) {
  match name {
    "label" => Str("count is \{self.counters.get(handle).unwrap()}")
    // a `@when` filter: called with (key, item, iter-data), answers a boolean
    "nonZero" =>
      match args {
        [_, Num(v), ..] => Bool(v != 0.0)
        _ => Bool(true)
      }
    _ => Null
  }
}

///|
impl Guest for FakeGuest with fn with_field(self, handle, name, v) {
  if self.titles.get(handle) is Some(_) {
    return match (name, v) {
      ("title", Str(t)) => {
        let h = self.next.val
        self.next.val = h + 1
        self.titles[h] = t
        Some(h)
      }
      _ => None
    }
  }
  match self.pairs.get(handle) {
    Some((l, r)) =>
      // nested-child write-through: the new child arrives as a DynObj value
      match (name, child_handle(v)) {
        ("left", Some(h)) => Some(self.alloc_pair(h, r))
        ("right", Some(h)) => Some(self.alloc_pair(l, h))
        _ => None
      }
    None =>
      match (name, v) {
        ("count", Num(n)) => Some(self.next_of(handle, n))
        _ => None
      }
  }
}

///|
/// Bytes only this guest reads: "count|h1,h2,…", which is deliberately NOT
/// JSON and not the declared-field shape — a host that could parse it would
/// prove nothing about the opaque half of the contract.
///
/// A Pair persists nothing, so the two paths are both exercised: its children
/// are instances, and the host rebuilds it from the fields instead.
impl Guest for FakeGuest with fn persist(self, handle) {
  guard self.pairs.get(handle) is None else { return b"" }
  guard self.counters.get(handle) is Some(count) else { return b"" }
  let history = self.histories
    .get(handle)
    .unwrap_or([])
    .map(n => n.to_int().to_string())
    .join(",")
  @utf8.encode("\{count.to_int()}|\{history}")
}

///|
impl Guest for FakeGuest with fn restore(self, component, state) {
  guard component == "Counter" else { return None }
  let text = @utf8.decode(state[:]) catch { _ => return None }
  let parts = text.split("|").map(v => v.to_owned()).collect()
  guard parts.length() == 2 else { return None }
  let count = @string.parse_double(parts[0]) catch { _ => return None }
  let history : Array[Double] = []
  for p in parts[1].split(",") {
    if p.length() > 0 {
      history.push(@string.parse_double(p.to_owned()) catch { _ => 0.0 })
    }
  }
  Some(self.alloc(count, history~))
}

///|
impl Guest for FakeGuest with fn drop_instance(self, handle) {
  self.counters.remove(handle) |> ignore
  self.histories.remove(handle) |> ignore
  self.pairs.remove(handle) |> ignore
}

///|
/// A field with no v3 metadata. Most of this fixture is about how the contract
/// BEHAVES, and spelling three blanks per field there would bury it; the
/// documented and constrained shapes are exercised in the parsing tests below.
fn plain_field(name : String, ty : Int) -> DynFieldDef {
  { name, ty, doc: "", required: false, constraint: None }
}

///|
/// The policy these tests register under.
///
/// They are about the MECHANICS — dispatch, identity, migration, schemas — and
/// the fixture ships a scoped stylesheet, which the default (untrusted) policy
/// refuses. Saying so once here keeps that decision visible instead of making
/// every test look like it needed a permission it did not.
fn vouched() -> @policy.Policy {
  @policy.Policy::granted()
}

///|
fn counter_manifest() -> DynManifest {
  // `types` is the flat table a guest ships (WIT has no recursive types);
  // 0 = f64 for the counter's `count`, 1 = the Counter a Pair holds.
  let num_ty : DynTyDef = {
    kind: "ty-float",
    elem: None,
    items: [],
    name: "",
    members: [],
  }
  let counter_ty : DynTyDef = {
    kind: "ty-comp",
    elem: None,
    items: [],
    name: "Counter",
    members: [],
  }
  {
    api_version: 6,
    module_name: "counterlib",
    doc: "Sample counters, for exercising the contract.",
    version: "0.1.0",
    homepage: "",
    authors: [],
    capabilities: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Counter",
        doc: "A number with buttons to change it.",
        keywords: ["counter", "number", "tally"],
        category: "input",
        message_docs: { "inc": "Add one.", "counted": "The count changed." },
        views: [
          {
            name: "main",
            html: (
              #|<div class="counter">
              #|  <button class="dec" @on.click="dec">-</button>
              #|  <span class="count" @text=".count"></span>
              #|  <button class="inc" @on.click="inc">+</button>
              #|  <button class="double" @on.click="double">double</button>
              #|  <button class="notify" @on.click="notify">notify</button>
              #|  <button class="announce" @on.click="announce">announce</button>
              #|  <button class="triple" @on.click="triple">triple</button>
              #|  <button class="zero" @on.click="setCount 0">zero</button>
              #|  <span class="label" @text="$label"></span>
              #|  <ul class="hist"><li class="h" @each=".history" @when="nonZero" @text="@value"></li></ul>
              #|  <input class="kbd" @on.keydown+cancel="reset">
              #|</div>
            ),
          },
        ],
        types: [
          num_ty,
          { kind: "ty-list", elem: Some(0), items: [], name: "", members: [] },
        ],
        fields: [plain_field("count", 0), plain_field("history", 1)],
        // `setCount` is deliberately absent: it is the mutator the `count`
        // field implies, and the host answers it
        receives: ["init", "setTo"],
        intents: [],
        methods: ["label"],
        whens: ["nonZero"],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        // a named initial state a host can offer instead of a bare instance
        inits: [
          {
            name: "with-history",
            args: { "count": Num(3) },
            doc: "Starts at three.",
          },
        ],
        style: ".counter { color: red; }",
      },
      {
        name: "Pair",
        doc: "Two counters side by side.",
        keywords: [],
        category: "",
        message_docs: Map([]),
        views: [
          {
            name: "main",
            html: (
              #|<div class="pair">
              #|  <button class="resetleft" @on.click="resetLeft">reset left</button>
              #|  <div class="left"><x render=".left"></div>
              #|  <div class="right"><x render=".right"></div>
              #|</div>
            ),
          },
        ],
        types: [counter_ty],
        fields: [plain_field("left", 0), plain_field("right", 0)],
        // NOTE for the placeholder tests below: `left`/`right` name `Counter`,
        // which is a component of THIS bundle, so they are the guest's own
        // nested children and the host must not fill them. `Framed` is the
        // other case.
        // `resetLeft` is ALSO the generated mutator name for a `left` field;
        // saying so here is what makes it the guest's
        receives: [],
        intents: ["counted"],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        // the bundle serves this one itself; the host never sees the name
        serves: ["triple"],
        inits: [],
        style: "",
      },
      // A guest with a HOLE in its own layout: `body` names `Filler`, which is
      // a component of the HOST's module and not of this bundle, so the guest
      // can neither build it nor hold it — it declares the field, renders it,
      // and the host fills it.
      {
        name: "Framed",
        doc: "A frame around something the host provides.",
        keywords: [],
        category: "",
        message_docs: Map([]),
        views: [
          {
            name: "main",
            html: (
              #|<div class="framed">
              #|  <span class="frame-title" @text=".title"></span>
              #|  <button class="retitle" @on.click="setTitle 'renamed'">rename</button>
              #|  <div class="frame-body"><x render=".body"></div>
              #|</div>
            ),
          },
        ],
        types: [
          { kind: "ty-text", elem: None, items: [], name: "", members: [] },
          {
            kind: "ty-comp",
            elem: None,
            items: [],
            name: "Filler",
            members: [],
          },
        ],
        fields: [plain_field("title", 0), plain_field("body", 1)],
        receives: [],
        intents: [],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        inits: [],
        style: "",
      },
    ],
  }
}

///|
/// A host shell with a slot for the guest instance, a note fed by the
/// guest's bubbled control message, and nothing else.
fn shell_module() -> @component.ModuleDef {
  let shell = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="shell">
          #|  <span class="note" @text=".note"></span>
          #|  <ul class="seq"><li class="s" @each=".slot" @text="@value"></li></ul>
          #|  <x render=".slot">
          #|</div>
        ),
      ),
    },
    name="Shell",
    init=TestShellState::{ slot: Null, note: "" },
    update=(s : TestShellState, msg, _ctx) => {
      match msg {
        Receive("setSlot", [v, ..]) => Next({ ..s, slot: v })
        Intent("counterChanged", [v, ..]) => Next({ ..s, note: v.str() })
        // only reached when nothing below stopped the bubble
        Intent("counted", [v, ..]) =>
          Next({ ..s, note: "counted \{v.to_display_string()}" })
        _ => Unhandled
      }
    },
  )
  @component.ModuleDef::new(name="shelltest", components=[shell, filler_comp()])
}

///|
priv struct TestShellState {
  slot : @tutuca.Value
  note : String
}

///|
/// A HOST component a guest can name but never build: it belongs to the host's
/// module, so `control.make-instance` (same-bundle by contract) cannot reach
/// it and no WIT `value` can carry it back. It stands in for the universal
/// component a guest asks for when it wants a hole in its own layout.
///
/// It holds state so the tests can prove the interesting half: that what a
/// person does inside a placeholder survives the guest around it changing.
priv struct FillerState {
  note : String
}

///|
impl @component.Fields for FillerState with fn schema() {
  @component.SchemaInfo::new(
    name="Filler",
    fingerprint="filler-1",
    fields=[@component.FieldInfo::new("note", TyText)],
    view_handlers=["bump"],
  )
}

///|
impl @component.Fields for FillerState with fn encode(s) {
  { "note": Str(s.note) }
}

///|
impl @component.Fields for FillerState with fn decode(f) {
  guard f.get("note") is Some(Str(note)) else { return None }
  Some({ note, })
}

///|
fn filler_comp() -> @component.Component {
  @component.component(
    name="Filler",
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="filler"><span class="filler-note" @text=".note"></span><button class="filler-bump" @on.click="bump">bump</button></div>
        ),
      ),
    },
    init=FillerState::{ note: "fresh" },
    update=(s, msg, _ctx) => {
      match msg {
        Receive("bump", _) => Next({ note: s.note + "!" })
        _ => Unhandled
      }
    },
  )
}

///|
fn mount_with_bundle(fake : FakeGuest) -> (@harness.Harness, Bundle) raise {
  let h = @harness.mount(shell_module(), "Shell")
  // what a host does after mounting: sweep superseded guest handles at the end
  // of every drained cascade (see install_gc)
  install_gc(h.app.transactor)
  let bundle = register_bundle(
    h.app.scope,
    fake,
    counter_manifest(),
    policy=vouched(),
  )
  fake.bundle.val = Some(bundle)
  (h, bundle)
}

///|
test "bundle mounts into a live app and dispatches through stock machinery" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  inspect(h.find_all(".counter").length(), content="0")
  guard! bundle.make_instance("Counter", args={ "count": Num(10) })
    is Some(inst0)

  // seeding the instance is a plain state change
  h.send_at_root("setSlot", args=[inst0.to_value()])
  inspect(h.text(".count"), content="10")
  inspect(h.text(".label"), content="count is 10")

  // input dispatch: guest returns a successor handle -> new DynObj -> render;
  // the cascade drains, the render reads the successor, and the sweep drops
  // the handle it replaced
  h.click(".inc")
  inspect(h.text(".count"), content="11")
  assert_true(fake.counters.get(inst0.handle()) is None)
  inspect(superseded_count(), content="0")
  h.click(".dec")
  inspect(h.text(".count"), content="10")

  // control drain: guest Emit -> ctx.bubble -> shell's bubble handler
  inspect(h.text(".note"), content="")
  h.click(".notify")
  inspect(h.text(".note"), content="changed!")
  inspect(h.text(".count"), content="10")

  // eager collection leaves only the live instance behind
  collect_superseded()
  inspect(superseded_count(), content="0")
  assert_true(fake.counters.length() == 1)
}

///|
test "a guest successor keeps its origin and moves its revision" {
  // A guest instance is replaced by a NEW DynObj around a new handle on every
  // dispatch, so without carrying the bucket forward each update would look
  // like a brand-new component to the render cache and never hit.
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(a)
  guard! bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(b)
  // Two live guest instances of one component are two handles, so they spread
  // across buckets even though their state is identical.
  guard! a.to_value().identity() is Some(id_a)
  guard! b.to_value().identity() is Some(id_b)
  assert_not_eq(id_a.to_hex(), id_b.to_hex())
  assert_eq(id_a.rev, 0)
  h.send_at_root("setSlot", args=[a.to_value()])
  h.click(".inc")
  inspect(h.text(".count"), content="11")
  guard! h.app.root_value().field("slot").identity() is Some(after)
  assert_eq(after.to_hex(), id_a.to_hex())
  assert_eq(after.rev, 1)
  collect_superseded()
}

///|
test "a guest `request` round-trips through a host IntentFn" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  h.app.scope.register_intent_handlers({
    "double": [
      IntentFn((call, answer) => {
        match call.args {
          [Num(n)] => answer(Ok(Num(n * 2.0)))
          _ => answer(Failed(Str("bad args")))
        }
      }),
    ],
  })
  guard! bundle.make_instance("Counter", args={ "count": Num(21) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  inspect(h.text(".count"), content="21")
  // the guest's `request` becomes an `intent lex` at the host, and the answer
  // comes back as an ordinary message named by `on_ok_name` — which the guest
  // hears in its `receive` bucket and answers with the doubled successor
  h.click(".double")
  inspect(h.text(".count"), content="42")
}

///|
test "nested guest children render and dispatch through two DynObj levels" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Pair") is Some(pair)
  h.send_at_root("setSlot", args=[pair.to_value()])

  // both children render with their own counts
  debug_inspect(h.texts(".count"), content="[\"1\", \"100\"]")

  // clicking the LEFT child's + dispatches to the child leaf; the spine
  // rebuild writes through the Pair via the handle protocol field
  h.click(".inc") // first .inc in document order = left
  debug_inspect(h.texts(".count"), content="[\"2\", \"100\"]")
  h.click(".inc", nth=1) // right child
  debug_inspect(h.texts(".count"), content="[\"2\", \"101\"]")
  // pair successors were created for each write-through
  assert_true(fake.pairs.length() >= 1)
}

///|
test "event modifiers in guest views dispatch through stock parsing" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(5) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  inspect(h.text(".count"), content="5")
  // @on.keydown+cancel="reset" — the modifier gates on Escape (host-side
  // modifier semantics apply to guest views for free); Enter is filtered
  h.key_down(".kbd", "Enter")
  inspect(h.text(".count"), content="5")
  h.key_down(".kbd", "Escape")
  inspect(h.text(".count"), content="0")
}

///|
test "migrate_instance rebuilds state from the JSON projection" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(a)
  guard! bundle.migrate_instance(a.to_value(), "Counter") is Some(b)
  assert_true(a.handle() != b.handle())
  assert_true(fake.counters.get(b.handle()) is Some(10.0))
  // non-guest values don't migrate
  assert_true(bundle.migrate_instance(Str("nope"), "Counter") is None)
}

///|
/// The guest's own bytes come back as the guest's own state — including the
/// half the declared fields do not name. Here that is the history: the fake
/// writes it into its bytes and the constructor ignores an unknown arg, so an
/// instance whose history survives could only have come back through the
/// guest.
test "a snapshot restores through the guest's own bytes" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(7) }) is Some(a)
  let a = a.with_persist_id("notes/1")
  // one update later: the successor keeps the id and gains a history entry
  guard! a.obj_with_field("count", Num(8)) is Some(bumped)
  guard! bundle.snapshot(bumped) is Some(snap)
  assert_eq(snap.module_, "counterlib")
  assert_eq(snap.component, "Counter")
  assert_eq(snap.id, "notes/1")
  assert_true(snap.has_state())
  guard! bundle.restore(snap) is Some(back)
  assert_eq(fake.counters.get(back.handle()).unwrap(), 8.0)
  // the history is the proof: it rode in the guest's bytes
  @debug.assert_eq(fake.histories.get(back.handle()).unwrap(), [7.0])
  // and it comes back under the same name, so saving it again lands on the
  // same key rather than accumulating one instance per reload
  assert_eq(back.obj_persist_id().unwrap(), "notes/1")
}

///|
/// A component that persists NOTHING still survives, through the projection
/// the host can make on its own. The Pair is the case: its state is two child
/// instances, its `persist` is empty, and it comes back rebuilt by its
/// constructor.
test "a component that does not persist restores from its declared fields" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Pair") is Some(p)
  guard! bundle.snapshot(p.to_value()) is Some(snap)
  assert_false(snap.has_state())
  // minted rather than blank: every instance has a name, and it says what it
  // is an instance of
  assert_true(snap.id.has_prefix("counterlib/Pair#"))
  guard! bundle.restore(snap) is Some(back)
  assert_true(back.handle() != p.handle())
  assert_true(fake.pairs.get(back.handle()) is Some(_))
}

///|
/// Bytes the guest refuses fall back to the same projection, which is what
/// makes changing a persisted format survivable: the state the guest could no
/// longer read is lost and the declared fields are not.
test "a guest refusing its own bytes falls back to the fields" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(3) }) is Some(a)
  guard! bundle.snapshot(a.to_value()) is Some(snap)
  let stale = { ..snap, state: @utf8.encode("from a format ago") }
  guard! bundle.restore(stale) is Some(back)
  assert_eq(fake.counters.get(back.handle()).unwrap(), 3.0)
}

///|
/// The round trip a page actually makes: through a store, as text.
test "a snapshot survives a store round trip" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  let store = @persist.MemStore::new()
  guard! bundle.make_instance("Counter", args={ "count": Num(41) }) is Some(a)
  let a = a.with_persist_id("counter/main")
  guard! bundle.snapshot(a.to_value()) is Some(snap)
  assert_true(@persist.save(store, snap))
  @debug.assert_eq(@persist.saved_ids(store), ["counter/main"])
  guard! @persist.load(store, "counter/main") is Some(read_back)
  assert_eq(read_back, snap)
  guard! bundle.restore(read_back) is Some(back)
  assert_eq(fake.counters.get(back.handle()).unwrap(), 41.0)
  @persist.forget(store, "counter/main")
  assert_true(@persist.load(store, "counter/main") is None)
}

///|
/// An instance nobody named is not stored, rather than stored somewhere it
/// will never be looked for.
test "an unnamed instance is not saved" {
  let store = @persist.MemStore::new()
  let anonymous : @persist.Snapshot = {
    module_: "counterlib",
    component: "Counter",
    id: "",
    state: b"",
    fields: Json::object({}),
  }
  assert_false(@persist.save(store, anonymous))
  assert_eq(store.size(), 0)
}

///|
test "styles of synthesized components join the app's compiled styles" {
  let fake = FakeGuest::new()
  let (h, _) = mount_with_bundle(fake)
  assert_true(h.styles().contains(".counter { color: red; }"))
}

///|
test "event_names reflects a bundle registered after boot" {
  let h = @harness.mount(shell_module(), "Shell")
  // The host module has no keydown handler; the guest's counter view adds one
  // (`@on.keydown+cancel="reset"`). Not `click` — the host's own `Filler`, the
  // component a guest's placeholder names, has a button.
  assert_false(h.app.event_names().contains("keydown"))
  let _ = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    counter_manifest(),
    policy=vouched(),
  )
  assert_true(h.app.event_names().contains("keydown"))
}

///|
test "a guest's declared schema describes, compares and projects it" {
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(7) }) is Some(a)
  guard! bundle.make_instance("Counter", args={ "count": Num(7) }) is Some(b)
  guard! bundle.make_instance("Counter", args={ "count": Num(8) }) is Some(c)
  guard! a.to_value() is Obj(oa)
  guard! b.to_value() is Obj(ob)
  guard! c.to_value() is Obj(oc)
  // structural equality over the DECLARED fields — the guest implements none
  assert_true(oa.obj_eq(ob))
  assert_false(oa.obj_eq(oc))
  // the JSON projection walks the same fields (no guest `to-json`)
  inspect(
    a.to_value().to_json().stringify(),
    content="{\"count\":7,\"history\":[]}",
  )
  // ...and so does the debug rendering
  inspect(oa.obj_debug(), content="Counter{count: RNum(7), history: RList([])}")
}

///|
test "a guest gets the generated mutators its schema implies" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  inspect(h.text(".count"), content="10")
  // `@on.click="setCount 0"` in the GUEST's view: no such handler crosses to
  // the guest — the mutator the schema implies writes through with-field
  h.click(".zero")
  inspect(h.text(".count"), content="0")
}

///|
test "inputs are read off the compiled views, not declared" {
  let (_h, bundle) = mount_with_bundle(FakeGuest::new())
  guard! bundle.schema_of("Counter") is Some(schema)
  // every @on handler the view names, and nothing else: `setCount` is a
  // mutator the schema implies, not a name the guest answers
  debug_inspect(
    schema.view_handlers,
    content=(
      #|[
      #|  "dec",
      #|  "inc",
      #|  "double",
      #|  "notify",
      #|  "announce",
      #|  "triple",
      #|  "setCount",
      #|  "reset",
      #|]
    ),
  )
  debug_inspect(schema.field_names(), content="[\"count\", \"history\"]")
}

///|
test "a guest child's bubble reaches a guest PARENT, which can stop it" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Pair") is Some(pair)
  h.send_at_root("setSlot", args=[pair.to_value()])
  debug_inspect(h.texts(".count"), content="[\"1\", \"100\"]")
  // the left child emits "counted"; the Pair declares that bubble and hears it
  // one level up, swapping the two children...
  h.click(".announce")
  debug_inspect(h.texts(".count"), content="[\"100\", \"1\"]")
  // ...and its stop_propagation keeps the bubble from reaching the host shell
  inspect(h.text(".note"), content="")
}

///|
test "a bubble no guest stops still reaches the host" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(3) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  // no Pair in between: the same emit walks all the way up to the shell
  h.click(".announce")
  inspect(h.text(".note"), content="counted 3")
}

///|
test "a guest addresses its own subtree by relative path" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Pair") is Some(pair)
  h.send_at_root("setSlot", args=[pair.to_value()])
  debug_inspect(h.texts(".count"), content="[\"1\", \"100\"]")
  // `send-at [field("left")] "setTo" [0]`: the left CHILD's receive handler runs
  h.click(".resetleft")
  debug_inspect(h.texts(".count"), content="[\"0\", \"100\"]")
}

///|
test "request opts route the response to the name the guest asked for" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  h.app.scope.register_intent_handlers({
    "double": [
      IntentFn((call, answer) => {
        match call.args {
          [Num(n)] => answer(Ok(Num(n * 2.0)))
          _ => answer(Failed(Str("bad args")))
        }
      }),
    ],
  })
  guard! bundle.make_instance("Counter", args={ "count": Num(21) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  // the guest requested with on_ok_name="doubled", so the response dispatches
  // "doubled" with just the value — not "double" with [result, error]
  h.click(".double")
  inspect(h.text(".count"), content="42")
}

///|
test "a bundle serves its own requests, ahead of the host's" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  // a host handler of the SAME name, which the guest's must win over
  h.app.scope.register_intent_handlers({
    "triple": [
      IntentFn((call, answer) => {
        match call.args {
          [Num(n)] => answer(Ok(Num(n * 100.0)))
          _ => answer(Failed(Str("bad args")))
        }
      }),
    ],
  })
  guard! bundle.make_instance("Counter", args={ "count": Num(5) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  h.click(".triple")
  // 5 * 3 (the bundle's own handler), not 5 * 100 (the host's)
  inspect(h.text(".count"), content="15")
  debug_inspect(fake.served, content="[\"triple\"]")
}

///|
test "a guest answers a view's @when filter" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(0) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  // history is empty
  debug_inspect(h.texts("li.h"), content="[]")
  h.click(".inc") // history [0]
  h.click(".inc") // history [0, 1]
  h.click(".inc") // history [0, 1, 2]
  // `@when="nonZero"` reaches the guest's call-method with (key, item, iter)
  // and its answer filters the iteration: the leading 0 is gone
  debug_inspect(h.texts("li.h"), content="[\"1\", \"2\"]")
}

///|
test "component_names lists the manifest's components in order" {
  let (_, bundle) = mount_with_bundle(FakeGuest::new())
  debug_inspect(
    bundle.component_names(),
    content="[\"Counter\", \"Pair\", \"Framed\"]",
  )
}

///|
test "manifest parses from the bridge's JSON projection" {
  let json =
    #|{"apiVersion": 8, "moduleName": "counterlib", "components": [
    #|  {"name": "Counter",
    #|   "views": [{"name": "main", "html": "<div>{.count}</div>"}],
    #|   "types": [{"kind": "ty-int", "elem": null, "items": [], "name": "", "members": []},
    #|             {"kind": "ty-list", "elem": 0, "items": [], "name": "", "members": []}],
    #|   "fields": [{"name": "count", "ty": 0}, {"name": "history", "ty": 1}],
    #|   "receives": ["init", "double"], "intents": [],
    #|   "methods": ["label"], "style": ""}]}
  let m = DynManifest::from_json_string(json)
  inspect(m.module_name, content="counterlib")
  inspect(m.components[0].views[0].html, content="<div>{.count}</div>")
  // the flat type table rebuilds into nested TyInfo
  let fields = m.components[0].field_infos()
  debug_inspect(
    fields.map(f => "\{f.name}:\{f.ty.show_source()}"),
    content="[\"count:Int\", \"history:Array[Int]\"]",
  )
  debug_inspect(m.components[0].methods, content="[\"label\"]")
}

///|
/// The default policy is the untrusted one, and `register_bundle` enforces it
/// before it parses anything. Three refusals, end to end, from the same
/// fixture the rest of the suite registers under a vouched policy.
test "the default policy refuses CSS, capabilities and a bomb" {
  let h = @harness.mount(shell_module(), "Shell")
  let base = counter_manifest()
  let refused = (m : DynManifest) => {
    let mut ok = true
    // no `policy=`: this is what a page gets when it just drops a bundle on
    try register_bundle(h.app.scope, FakeGuest::new(), m) |> ignore catch {
      _ => ok = false
    }
    !ok
  }
  // the fixture ships a scoped stylesheet, and an untrusted bundle may not
  assert_true(refused(base))
  // ...the same bundle without it is fine, which is what every sample guest
  // already does — the strict default costs nothing real
  let styleless : DynManifest = {
    ..base,
    module_name: "styleless",
    components: base.components.map(c => ({ ..c, style: "" } : DynComponentDef)),
  }
  assert_false(refused(styleless))
  // a capability nobody granted
  assert_true(
    refused({
      ..styleless,
      module_name: "clocky",
      capabilities: [{ cap: CapClock, reason: "stamps entries" }],
    }),
  )
  // and a manifest too large to parse before rendering anything
  let many : Array[DynComponentDef] = []
  for i in 0..<200 {
    many.push({ ..styleless.components[0], name: "C\{i}" })
  }
  assert_true(refused({ ..styleless, module_name: "huge", components: many }))
}

///|
/// Hold the policy decision at the registration seam too: this is where a
/// parsed guest view either joins the shared app registry or disappears.
test "untrusted registration blocks DOM egress but keeps custom elements" {
  let register_view = (html : String) => {
    let h = @harness.mount(shell_module(), "Shell")
    let base = counter_manifest()
    let manifest : DynManifest = {
      ..base,
      module_name: "view-policy",
      components: [
        { ..base.components[0], style: "", views: [{ name: "main", html }] },
      ],
    }
    let mut ok = true
    try
      register_bundle(h.app.scope, FakeGuest::new(), manifest) |> ignore
    catch {
      _ => ok = false
    }
    ok
  }
  assert_false(register_view("<a :href=\".count\">leave</a>"))
  assert_false(register_view("<div @setinnermd=\".count\"></div>"))
  assert_true(
    register_view("<x-picker :items=\".history\" mode=\"compact\"></x-picker>"),
  )
}

///|
/// The same seam, with the one capability that is about the view rather than
/// about an import. A page grants the origins it means to allow, and the
/// bundle's own views are what get held against them.
test "cap-external-urls lets a registered guest view name a pinned image" {
  let register_view = (html : String, policy : @policy.Policy) => {
    let h = @harness.mount(shell_module(), "Shell")
    let base = counter_manifest()
    let manifest : DynManifest = {
      ..base,
      module_name: "avatar-policy",
      components: [
        { ..base.components[0], style: "", views: [{ name: "main", html }] },
      ],
    }
    let mut ok = true
    try
      register_bundle(h.app.scope, FakeGuest::new(), manifest, policy~)
      |> ignore
    catch {
      _ => ok = false
    }
    ok
  }
  let strict = @policy.Policy::untrusted()
  let cdn = strict.allowing_external_urls(["https://cdn.example"])
  let pinned = "<img :src=\"$'https://cdn.example/a/{.count}.png'\" />"
  // The picture the report asked for: allowed once a page has said which CDN,
  // and refused by the same page for any other origin or a computed one.
  assert_true(register_view(pinned, cdn))
  assert_false(register_view(pinned, strict))
  assert_false(register_view("<img :src=\".count\" />", cdn))
  assert_false(
    register_view("<img src=\"https://elsewhere.test/a.png\" />", cdn),
  )
  // A bundle that ASKS for it is refused by a page that has not decided, which
  // is the same bargain every other capability makes.
  let h = @harness.mount(shell_module(), "Shell")
  let base = counter_manifest()
  let asking : DynManifest = {
    ..base,
    module_name: "asking",
    components: [
      {
        ..base.components[0],
        style: "",
        views: [{ name: "main", html: pinned }],
      },
    ],
    capabilities: [{ cap: CapExternalUrls, reason: "shows avatars" }],
  }
  let mut refused = false
  try register_bundle(h.app.scope, FakeGuest::new(), asking) |> ignore catch {
    _ => refused = true
  }
  assert_true(refused)
}

///|
/// The one view construct a host cannot inspect before it runs, and therefore
/// the one it refuses. Note WHERE the refusal lands: nothing of a refused
/// bundle reaches the shared component registry, so its markup never
/// contributes an event name or a CSS class to the page that turned it down.
test "a guest view that sets markup directly is refused" {
  let h = @harness.mount(shell_module(), "Shell")
  let base = counter_manifest()
  let m : DynManifest = {
    ..base,
    module_name: "sneakylib",
    components: [
      {
        ..base.components[0],
        name: "Sneaky",
        views: [
          {
            name: "main",
            html: "<div class=\"sneaky-marker\" @dangerouslysetinnerhtml=\".payload\"></div>",
          },
        ],
      },
    ],
  }
  let register = (man : DynManifest) => {
    let mut ok = true
    try
      register_bundle(h.app.scope, FakeGuest::new(), man, policy=vouched())
      |> ignore
    catch {
      // `register_bundle` also propagates the compiler's MacroError, so its
      // raise type is the open one and the payload cannot be matched out here.
      // What the test is for is the DECISION, not its wording.
      _ => ok = false
    }
    ok
  }
  assert_false(register(m))
  // Nothing of the refused bundle reached the shared registry — which is what
  // `collect_classes` and `compile_styles` walk, so a turned-down bundle does
  // not shape the page's stylesheet either.
  assert_false(h.app.scope.comps.collect_classes().contains("sneaky-marker"))
  // The same bundle without the one construct is fine: it is the directive
  // that is refused, not the guest.
  let ok_m : DynManifest = {
    ..m,
    module_name: "tidylib",
    components: [
      {
        ..m.components[0],
        views: [{ name: "main", html: "<div class=\"tidy-marker\"></div>" }],
      },
    ],
  }
  assert_true(register(ok_m))
  assert_true(h.app.scope.comps.collect_classes().contains("tidy-marker"))
}

///|
/// The v3 additions are all metadata, so nothing downstream fails without
/// them — which is exactly why they need a test of their own. A field's `doc`
/// and `constraint` are the two facts neither the type table nor the views can
/// supply, and they are what the catalog ranks on and the generated form
/// validates with.
test "catalog metadata parses: docs, constraints and capability requests" {
  let json =
    #|{"apiVersion": 8, "moduleName": "formlib",
    #| "doc": "Form controls.", "version": "1.2.0", "authors": ["ana"],
    #| "capabilities": [{"cap": "cap-clock", "reason": "stamps entries"},
    #|                  {"cap": "cap-teleport", "reason": "?"}],
    #| "components": [
    #|  {"name": "Signup", "doc": "Collects an address.",
    #|   "keywords": ["form", "email"], "category": "input",
    #|   "messageDocs": [{"name": "submit", "doc": "Send it."}, {"doc": "orphan"}],
    #|   "views": [{"name": "main", "html": "<div></div>"}],
    #|   "types": [{"kind": "ty-text", "elem": null, "items": [], "name": "", "members": []}],
    #|   "fields": [{"name": "email", "ty": 0, "doc": "Where to write.",
    #|               "required": true,
    #|               "constraint": {"maxLen": 254, "format": "email",
    #|                              "enumJson": "", "defaultJson": "\"a@b.c\"",
    #|                              "pattern": ""}}],
    #|   "receives": [], "intents": [], "methods": [],
    #|   "inits": [{"name": "blank", "argsJson": "{}", "doc": "Nothing filled in."}],
    #|   "style": ""}]}
  let m = DynManifest::from_json_string(json)
  inspect(m.doc, content="Form controls.")
  inspect(m.version, content="1.2.0")
  // an unknown capability is KEPT, not dropped: the host has to be able to say
  // which one it is refusing
  debug_inspect(
    m.capabilities.map(c => c.cap),
    content="[CapClock, CapUnknown(\"cap-teleport\")]",
  )
  let c = m.components[0]
  inspect(c.doc, content="Collects an address.")
  inspect(c.category, content="input")
  debug_inspect(c.keywords, content="[\"form\", \"email\"]")
  // message-docs become a lookup; the entry naming nothing is dropped rather
  // than keyed on ""
  debug_inspect(
    c.message_docs,
    content=(
      #|{ "submit": "Send it." }
    ),
  )
  inspect(c.inits[0].doc, content="Nothing filled in.")
  let f = c.fields[0]
  inspect(f.doc, content="Where to write.")
  assert_true(f.required)
  guard! f.constraint is Some(k)
  debug_inspect(k.max_len, content="Some(254)")
  inspect(k.format, content="email")
  // "" is the contract's spelling for "not stated", so an empty enumeration is
  // None rather than an empty array — the two mean different things to a form
  assert_true(k.enum_values is None)
  debug_inspect(
    k.default,
    content=(
      #|Some(RStr("a@b.c"))
    ),
  )
  assert_true(k.min is None)
}

///|
/// A guest that says nothing about itself still registers. Every v3 addition
/// is optional in practice, because jco drops an empty `option` and a
/// hand-written manifest should not have to spell out blanks.
test "a manifest with no catalog metadata still parses" {
  let json =
    #|{"apiVersion": 8, "moduleName": "bare", "components": [
    #|  {"name": "C", "views": [{"name": "main", "html": "<div></div>"}],
    #|   "types": [], "fields": [],
    #|   "receives": [], "intents": [], "methods": [],
    #|   "style": ""}]}
  let m = DynManifest::from_json_string(json)
  inspect(m.doc, content="")
  debug_inspect(m.capabilities, content="[]")
  inspect(m.components[0].category, content="")
  debug_inspect(m.components[0].message_docs, content="{}")
}

///|
test "a cyclic or out-of-range type index reads as `any`, not a hang" {
  let json =
    #|{"apiVersion": 8, "moduleName": "m", "components": [
    #|  {"name": "C", "views": [{"name": "main", "html": "<div></div>"}],
    #|   "types": [{"kind": "ty-list", "elem": 0, "items": [], "name": "", "members": []}],
    #|   "fields": [{"name": "loop", "ty": 0}, {"name": "gone", "ty": 9}],
    #|   "receives": [], "intents": [], "methods": [],
    #|   "style": ""}]}
  let m = DynManifest::from_json_string(json)
  let fields = m.components[0].field_infos()
  // the guard bottoms out in `any` at its depth limit; the missing index too
  assert_true(fields[0].ty.show_source().has_prefix("Array["))
  inspect(fields[1].ty.show_source(), content="Any")
}

///|
test "manifest with wrong api version is rejected" {
  let bad =
    #|{"apiVersion": 1, "moduleName": "x", "components": []}
  let mut failed = false
  let _ = DynManifest::from_json_string(bad) catch {
    _ => {
      failed = true
      {
        api_version: 0,
        module_name: "",
        doc: "",
        version: "",
        homepage: "",
        authors: [],
        capabilities: [],
        config: [],
        macros: [],
        components: [],
      }
    }
  }
  assert_true(failed)
}

///|
impl @component.Fields for TestShellState with fn encode(s) {
  { "slot": s.slot, "note": Str(s.note) }
}

///|
impl @component.Fields for TestShellState with fn decode(f) {
  let v_slot = f.get("slot").unwrap_or(Null)
  guard f.get("note") is Some(Str(v_note)) else { return None }
  Some({ slot: v_slot, note: v_note })
}

///|
impl @component.Fields for TestShellState with fn schema() {
  @component.SchemaInfo::new(fingerprint="test_shell_state", fields=[
    @component.FieldInfo::new("slot", TyAny),
    @component.FieldInfo::new("note", TyText),
  ])
}

///|
test "a bundle's views are linted at load" {
  let bad : DynManifest = {
    api_version: 6,
    module_name: "sloppylib",
    doc: "",
    version: "",
    homepage: "",
    authors: [],
    capabilities: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Sloppy",
        doc: "",
        keywords: [],
        category: "",
        message_docs: Map([]),
        // an unclosed <div> and a `.field` in a handler position: two things
        // no build step ever checked for a guest, because its views arrive at
        // RUNTIME
        views: [
          { name: "main", html: "<div><span @on.click=\".nope\">hi</div>" },
        ],
        types: [],
        fields: [],
        receives: [],
        intents: [],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        inits: [],
        style: "",
      },
    ],
  }
  let h = @harness.mount(shell_module(), "Shell")
  let bundle = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    bad,
    policy=vouched(),
  )
  let lines = bundle.diagnostics()
  assert_true(lines.length() > 0)
  // every line names the component and view it is about
  for line in lines {
    assert_true(line.contains("Sloppy/main"))
  }
  // ...and a clean bundle says nothing
  let (_h2, ok) = mount_with_bundle(FakeGuest::new())
  debug_inspect(ok.diagnostics(), content="[]")
}

///|
/// The failure this catches renders as NOTHING: a `$name` the manifest forgot
/// to declare never reaches `call-method`, evaluates to Null, and an attribute
/// bound to Null is omitted — so the guest author sees an element quietly
/// missing its class and the guest itself is never told it was asked.
test "a `$method` the manifest never declared is reported at load" {
  let float_ty : DynTyDef = {
    kind: "ty-float",
    elem: None,
    items: [],
    name: "",
    members: [],
  }
  let sloppy : DynManifest = {
    api_version: 6,
    module_name: "statlib",
    doc: "",
    version: "",
    homepage: "",
    authors: [],
    capabilities: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Stat",
        doc: "",
        keywords: [],
        category: "",
        message_docs: Map([]),
        views: [
          {
            name: "main",
            html: (
              #|<div :style="$boxStyle" :class="$valueClass">
              #|  <button @on.click="$setCount 0">zero</button>
              #|  <button @on.click="$bumpIt">bump</button>
              #|  <span @text="$'{.count} / {$boxStyl}'"></span>
              #|</div>
            ),
          },
        ],
        types: [float_ty],
        fields: [plain_field("count", 0)],
        receives: [],
        intents: [],
        // `$setCount` is absent on purpose: it is the mutator the `count` field
        // implies, so the host answers it and it must NOT be reported
        methods: ["boxStyle"],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        inits: [],
        style: "",
      },
    ],
  }
  let h = @harness.mount(shell_module(), "Shell")
  let bundle = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    sloppy,
    policy=vouched(),
  )
  inspect(
    bundle.diagnostics().join("\n"),
    content=(
      #|UNDECLARED_METHOD (warning) Stat/main: '$bumpIt' is not a method this component declares, so it evaluates to nothing and the attribute or directive reading it is dropped silently; add it to the component's declared methods
      #|UNDECLARED_METHOD (warning) Stat/main: '$boxStyl' is not a method this component declares, so it evaluates to nothing and the attribute or directive reading it is dropped silently; add it to the component's declared methods — did you mean '$boxStyle'?
      #|UNDECLARED_METHOD (warning) Stat/main: '$valueClass' is not a method this component declares, so it evaluates to nothing and the attribute or directive reading it is dropped silently; add it to the component's declared methods
    ),
  )
}

///|
test "a component's named initial states are offered by name" {
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  debug_inspect(bundle.init_names("Counter"), content="[\"with-history\"]")
  debug_inspect(bundle.init_names("Pair"), content="[]")
  guard! bundle.make_init("Counter", "with-history") is Some(c)
  assert_true(fake.counters.get(c.handle()) is Some(3.0))
  // the schema carries them too, so a descriptor reader sees them
  guard! bundle.schema_of("Counter") is Some(schema)
  debug_inspect(schema.init_names, content="[\"with-history\"]")
  // an unknown fixture is not a bare instance: the caller decides
  assert_true(bundle.make_init("Counter", "nope") is None)
}

///|
/// The placeholder half of the contract: a guest declaring a field whose type
/// names a component from ANOTHER module gets it filled by the host, and never
/// touches it.
///
/// This is the whole mechanism behind "a component with internal layout can
/// offer a hole for a person to fill". It has to work this way round because
/// the boundary allows nothing else: a WIT `value` has no case that can carry
/// a host component, so the guest cannot be handed one. It names the field,
/// renders it, and the host does the rest.
test "a foreign placeholder is filled by the host and never reaches the guest" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Framed", args={ "title": Str("panel") })
    is Some(framed)
  h.send_at_root("setSlot", args=[framed.to_value()])
  // The guest's own field, answered by the guest.
  assert_eq(h.text(".frame-title"), "panel")
  // The hole, filled with the component the field NAMED and rendered by the
  // guest's own view through `<x render=".body">`.
  assert_eq(h.text(".filler-note"), "fresh")
  // The guest was never told about it: asked for `body` it answers nothing,
  // and the host answered anyway.
  assert_true(Guest::get_field(fake, framed.handle(), "body") is None)
}

///|
test "what a person puts in a placeholder survives the guest around it changing" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Framed", args={ "title": Str("panel") })
    is Some(framed)
  h.send_at_root("setSlot", args=[framed.to_value()])
  // Use what is in the hole.
  h.click(".filler-bump")
  h.click(".filler-bump")
  assert_eq(h.text(".filler-note"), "fresh!!")
  // Now change the GUEST, which mints a successor handle. A successor is the
  // same logical instance one update later, so what the host is holding for it
  // has to come across — otherwise every keystroke in the guest would reset
  // whatever a person built inside it.
  h.click(".retitle")
  assert_eq(h.text(".frame-title"), "renamed")
  assert_eq(h.text(".filler-note"), "fresh!!")
}

///|
test "a same-bundle child is the guest's own, and the host does not fill it" {
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  // `Pair { left: Counter, right: Counter }` names components of its OWN
  // bundle. Those are nested children the guest made and owns — filling them
  // here would shadow the guest's values with host-built ones, and the two
  // cases are told apart by exactly that: same-bundle is the guest's, foreign
  // is a hole.
  guard! bundle.make_instance("Pair") is Some(pair)
  h.send_at_root("setSlot", args=[pair.to_value()])
  // The guest's own children, with the guest's own values.
  assert_eq(h.texts(".count"), ["1", "100"])
  assert_true(Guest::get_field(fake, pair.handle(), "left") is Some(_))
}

///|
/// `child_json` is what a value looks like on its way INTO a guest, and the
/// claim under test is the recursion: a nested child inside a LIST has to cross
/// as its handle, not as a copy of its fields under a name that no longer
/// refers to it.
///
/// This is the write half of nesting, and it used to only work one level deep.
/// A guest whose children sit in a list — a message holding reactions, a channel
/// holding threads — has a child return a successor, and the host writes the
/// parent's WHOLE LIST back with the new instance in it. With the single
/// top-level case that list arrived as plain data, the guest refused it, and the
/// interaction did nothing at all: the guest counted and the screen did not.
test "child_json encodes a nested guest instance at any depth" {
  let fake = FakeGuest::new()
  let (_, bundle) = mount_with_bundle(fake)
  guard! bundle.make_instance("Counter", args={ "count": Num(1) }) is Some(a)
  guard! bundle.make_instance("Counter", args={ "count": Num(2) }) is Some(b)
  let marker = (h : Int) => "{\"$dyn\":{\"handle\":\{h}}}"

  // the case that always worked: a scalar `comp` field
  inspect(child_json(a.to_value()).stringify(), content=marker(a.handle()))

  // a list of them — what a parent's list field is written back as
  inspect(
    child_json(List([a.to_value(), Num(7), b.to_value()])).stringify(),
    content="[\{marker(a.handle())},7,\{marker(b.handle())}]",
  )

  // and inside a map, and inside a list inside a map
  inspect(
    child_json(Map({ "who": a.to_value(), "all": List([b.to_value()]) })).stringify(),
    content="{\"who\":\{marker(a.handle())},\"all\":[\{marker(b.handle())}]}",
  )

  // anything that is not a guest instance is untouched
  inspect(
    child_json(List([Str("x"), Bool(true), Null])).stringify(),
    content="[\"x\",true,null]",
  )
}

///|
/// A bound the field's type cannot carry is named at load.
///
/// The manifest's constraint record spells "unstated" two ways — `null` or an
/// absent key for the four bounds, `""` for the strings beside them — and four
/// of the six keys are safe to write blank. Writing the record out in full,
/// which is what copying a sample guest's manifest teaches, therefore states
/// bounds nobody meant, and they fail quietly in three different ways. The
/// unambiguous ones are worth saying out loud: a bound that cannot apply to the
/// type was not a decision.
test "a bound the type cannot carry is a load-time hint" {
  let h = @harness.mount(shell_module(), "Shell")
  let bounded = (c : @jsonschema.Constraint) => {
    (Some(c) : @jsonschema.Constraint?)
  }
  let manifest : DynManifest = {
    ..counter_manifest(),
    components: [
      {
        ..counter_manifest().components[0],
        fields: [
          // a magnitude on text: dropped when validating (`v is Num`) and
          // dropped from the schema, so it does nothing but mislead a reader
          {
            name: "label",
            ty: 1,
            doc: "",
            required: false,
            constraint: bounded({
              ..@jsonschema.Constraint::none(),
              min: Some(0),
              max: Some(0),
            }),
          },
          // a length on a number, likewise
          {
            name: "count",
            ty: 0,
            doc: "",
            required: false,
            constraint: bounded({
              ..@jsonschema.Constraint::none(),
              max_len: Some(0),
            }),
          },
        ],
      },
    ],
  }
  let bundle = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    manifest,
    policy=vouched(),
  )
  let said = bundle.diagnostics().filter(d => d.has_prefix("INERT_CONSTRAINT"))
  assert_eq(said.length(), 3)
  assert_true(said[0].contains("Counter.label") && said[0].contains("'min'"))
  assert_true(said[1].contains("Counter.label") && said[1].contains("'max'"))
  assert_true(said[2].contains("Counter.count") && said[2].contains("'maxLen'"))
  // it says what to write instead, because the spelling is the whole trap
  assert_true(said[0].contains("`null`"))

  // …and a bound the type CAN carry is not mentioned: `maxLen` on text is a
  // real bound, including a zero, and second-guessing one is not this pass's
  // job.
  let fine : DynManifest = {
    ..manifest,
    components: [
      {
        ..manifest.components[0],
        fields: [
          {
            name: "label",
            ty: 1,
            doc: "",
            required: false,
            constraint: bounded({
              ..@jsonschema.Constraint::none(),
              max_len: Some(0),
            }),
          },
        ],
      },
    ],
  }
  let quiet = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    fine,
    policy=vouched(),
  )
  assert_eq(
    quiet.diagnostics().filter(d => d.has_prefix("INERT_CONSTRAINT")).length(),
    0,
  )
}

///|
/// A mastodon-shaped bundle: one config-origin variable, one view that spends
/// it, and a module name the caller varies so the `by_name` hot-swap does not
/// eat the previous registration mid-test.
fn config_manifest(module_name : String) -> DynManifest {
  let base = counter_manifest()
  {
    ..base,
    module_name,
    config: [
      {
        name: "mediaOrigin",
        ty: TyOrigin,
        default_: "https://files.mastodon.social/",
        doc: "where the pictures are",
      },
      {
        name: "instanceName",
        ty: TyText,
        default_: "mastodon.social",
        doc: "the server, as a person writes it",
      },
    ],
    components: [
      {
        ..base.components[0],
        style: "",
        views: [
          {
            name: "main",
            html: "<img :src=\"$'{$$mediaOrigin}avatars/{.count}.png'\" />",
          },
        ],
      },
    ],
  }
}

///|
/// The whole point: one bundle, two instances, two servers, no rebuild.
test "a config origin lets one bundle serve two instances" {
  let h = @harness.mount(shell_module(), "Shell")
  let hachyderm = @policy.Policy::untrusted().with_config([
    ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
    ("instanceName", @policy.text("hachyderm.io")),
  ])
  let masto = @policy.Policy::untrusted().with_config([
    ("mediaOrigin", @policy.origin("https://files.mastodon.social")),
    ("instanceName", @policy.text("mastodon.social")),
  ])
  let a = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    config_manifest("reader"),
    policy=hachyderm,
  )
  let b = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    config_manifest("reader"),
    policy=masto,
  )
  // Same module name, same code, different identity — which is what makes the
  // two survivable side by side rather than one evicting the other.
  assert_eq(a.module_name(), b.module_name())
  assert_not_eq(a.key(), b.key())
  // The guest reads its whole table; the text variable is in it too.
  debug_inspect(
    a.config().get("mediaOrigin"),
    content=(
      #|Some("https://files.hachyderm.io/")
    ),
  )
  debug_inspect(
    a.config().get("instanceName"),
    content=(
      #|Some("hachyderm.io")
    ),
  )
  debug_inspect(
    b.config().get("mediaOrigin"),
    content=(
      #|Some("https://files.mastodon.social/")
    ),
  )
  // Registering the same bundle with the SAME config is the same registration,
  // which is what keeps hot-swap meaning what it always meant.
  let again = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    config_manifest("reader"),
    policy=hachyderm,
  )
  assert_eq(a.key(), again.key())
}

///|
/// The trap this design has: `register_bundle` parses each view TWICE — once
/// into the tree that renders (`View::new`) and once into a throwaway tree the
/// policy screens (`screen_view`). If only one of them resolved `$$name`, the
/// check would be about a document nobody displays.
///
/// Held from both sides, because each failure looks like success from the
/// other: screening an unresolved tree refuses a bundle that is fine, and
/// screening a resolved tree while rendering an unresolved one passes a bundle
/// nothing checked.
test "the screened tree and the rendered tree resolve config the same way" {
  let register = (module_name : String, policy : @policy.Policy) => {
    let h = @harness.mount(shell_module(), "Shell")
    let mut ok = true
    try
      register_bundle(
        h.app.scope,
        FakeGuest::new(),
        config_manifest(module_name),
        policy~,
      )
      |> ignore
    catch {
      _ => ok = false
    }
    ok
  }
  // Bound: the screen resolves the origin, finds it pinned, and lets it
  // through. If the screen parsed without the config this would be false.
  assert_true(
    register(
      "screen-bound",
      @policy.Policy::untrusted().with_config([
        ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
      ]),
    ),
  )
  // Unbound: the screen sees a template with a hole where the origin goes and
  // refuses. If the screen were skipping the check this would be true, and a
  // view that renders nothing useful would have registered silently.
  assert_false(register("screen-unbound", @policy.Policy::untrusted()))
}

///|
/// Binding is granting — but only what was bound, and only when the host was
/// the one who bound it.
test "a manifest's own origin default is not a grant" {
  let h = @harness.mount(shell_module(), "Shell")
  // The manifest defaults to files.mastodon.social. A host that bound nothing
  // has granted nothing, so the view cannot spend it.
  let refused = try {
    register_bundle(
      h.app.scope,
      FakeGuest::new(),
      config_manifest("default-only"),
    )
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  // ...until the host says, in as many words, that it ships these bundles and
  // their defaults are its own decision.
  let trusting = @policy.Policy::untrusted().trusting_manifest_config()
  let b = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    config_manifest("default-trusted"),
    policy=trusting,
  )
  debug_inspect(
    b.config().get("mediaOrigin"),
    content=(
      #|Some("https://files.mastodon.social/")
    ),
  )
}

///|
/// The type is stated by both parties, and a disagreement is the case that
/// makes the redundancy worth it: without it a manifest could declare `origin`
/// for a variable a host bound as prose and turn a string into a network grant.
test "a config type the host and the manifest disagree about refuses" {
  let h = @harness.mount(shell_module(), "Shell")
  // The host bound `mediaOrigin` as ordinary text; the manifest calls it an
  // origin. Nothing here is a valid bundle.
  let mismatched = @policy.Policy::untrusted().with_config([
    ("mediaOrigin", @policy.text("https://files.hachyderm.io/")),
  ])
  let why = try {
    register_bundle(
      h.app.scope,
      FakeGuest::new(),
      config_manifest("mismatch"),
      policy=mismatched,
    )
    |> ignore
    ""
  } catch {
    e => e.message()
  }
  debug_inspect(
    why,
    content=(
      #|"bundle refused: config 'mediaOrigin' is declared 'origin' and this host bound it as 'text'"
    ),
  )
}

///|
/// A shared policy is the normal case — one page, one decision, many bundles —
/// so a name this bundle does not declare is worth SAYING and not worth
/// refusing over. The other reason to see it is a typo.
test "a bound name the bundle does not declare is a diagnostic" {
  let h = @harness.mount(shell_module(), "Shell")
  let base = counter_manifest()
  // No `config` section at all — the ordinary bundle, sharing the page's one
  // policy with the one bundle that does read a variable.
  let plain : DynManifest = {
    ..base,
    module_name: "no-config-here",
    components: [{ ..base.components[0], style: "" }],
  }
  let b = register_bundle(
    h.app.scope,
    FakeGuest::new(),
    plain,
    policy=@policy.Policy::untrusted().with_config([
      ("mediaOrigin", @policy.origin("https://files.hachyderm.io")),
    ]),
  )
  assert_true(
    b
    .diagnostics()
    .any(d => {
      d.contains(
        "this host bound 'mediaOrigin', which this bundle does not declare",
      )
    }),
  )
}
