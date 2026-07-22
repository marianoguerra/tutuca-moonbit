///| Blackbox tests: mount a guest bundle (via an in-process FakeGuest) into
/// a live app on memdom and drive it through the stock pipeline — render
/// reads fields lazily, clicks dispatch through the synthesized component's
/// compiled views, successors re-render, control messages drain via &Ctx,
/// requests round-trip, nested guest children dispatch through two DynObj
/// levels, and superseded guest handles are collected.

///|
priv struct FakeGuest {
  counters : Map[Int, Double]
  pairs : Map[Int, (Int, Int)]
  next : Ref[Int]
  bundle : Ref[Bundle?]
}

///|
fn FakeGuest::new() -> FakeGuest {
  { counters: Map([]), pairs: Map([]), next: { val: 0 }, bundle: { val: None } }
}

///|
fn FakeGuest::alloc(self : FakeGuest, count : Double) -> Int {
  let h = self.next.val
  self.next.val = h + 1
  self.counters[h] = count
  h
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
        _ => None
      }
  }
}

///|
impl Guest for FakeGuest with fn seq_entries(self, handle) {
  // counters iterate as a single ("h0", count) entry; pairs don't iterate
  if self.pairs.contains(handle) {
    None
  } else {
    Some([("h0", Num(self.counters.get(handle).unwrap()))])
  }
}

///|
impl Guest for FakeGuest with fn dispatch(self, handle, bucket, name, args) {
  let count = self.counters.get(handle).unwrap()
  match (bucket, name) {
    (Input, "inc") => { next: Some(self.alloc(count + 1.0)), msgs: [] }
    (Input, "dec") => { next: Some(self.alloc(count - 1.0)), msgs: [] }
    (Input, "double") => { next: None, msgs: [Request("double", [Num(count)])] }
    (Response, "double") =>
      match args {
        [Num(n), ..] => { next: Some(self.alloc(n)), msgs: [] }
        _ => { next: None, msgs: [] }
      }
    (Input, "notify") =>
      { next: None, msgs: [Emit("counterChanged", [Str("changed!")])] }
    (Input, "reset") => { next: Some(self.alloc(0.0)), msgs: [] }
    _ => { next: None, msgs: [] }
  }
}

///|
impl Guest for FakeGuest with fn call_method(self, handle, name, _args) {
  match name {
    "label" => Str("count is \{self.counters.get(handle).unwrap()}")
    _ => Null
  }
}

///|
impl Guest for FakeGuest with fn with_field(self, handle, name, v) {
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
        ("count", Num(n)) => Some(self.alloc(n))
        _ => None
      }
  }
}

///|
impl Guest for FakeGuest with fn to_json_string(self, handle) {
  match self.pairs.get(handle) {
    Some((l, r)) => "{\"left\": \{l}, \"right\": \{r}}"
    None => "{\"count\": \{self.counters.get(handle).unwrap()}}"
  }
}

///|
impl Guest for FakeGuest with fn drop_instance(self, handle) {
  self.counters.remove(handle) |> ignore
  self.pairs.remove(handle) |> ignore
}

///|
fn counter_manifest() -> DynManifest {
  {
    api_version: 1,
    module_name: "counterlib",
    components: [
      {
        name: "Counter",
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
              #|  <span class="label" @text="$label"></span>
              #|  <input class="kbd" @on.keydown+cancel="reset">
              #|</div>
            ),
          },
        ],
        input_handlers: ["inc", "dec", "double", "notify", "reset"],
        receive_handlers: ["init"],
        response_handlers: ["double"],
        method_names: ["label"],
        style: ".counter { color: red; }",
      },
      {
        name: "Pair",
        views: [
          {
            name: "main",
            html: (
              #|<div class="pair">
              #|  <div class="left"><x render=".left"></div>
              #|  <div class="right"><x render=".right"></div>
              #|</div>
            ),
          },
        ],
        input_handlers: [],
        receive_handlers: [],
        response_handlers: [],
        method_names: [],
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
          #|  <ul class="seq"><li @each=".slot" @text="@value"></li></ul>
          #|  <x render=".slot">
          #|</div>
        ),
      ),
    },
    name="Shell",
    init=TestShellState::{ slot: Null, note: "" },
    update=(s : TestShellState, msg, _ctx) => {
      match msg {
        Receive("setSlot", [v, ..]) => Some({ ..s, slot: v })
        Bubble("counterChanged", [v, ..]) => Some({ ..s, note: v.str() })
        _ => None
      }
    },
  )
  @component.ModuleDef::new(name="shelltest", components=[shell])
}

///|
priv struct TestShellState {
  slot : @tutuca.Value
  note : String
} derive(ToJson, FromJson)

///|
fn mount_with_bundle(fake : FakeGuest) -> (@harness.Harness, Bundle) raise {
  let h = @harness.mount(shell_module(), "Shell")
  let bundle = register_bundle(h.app.scope, fake, counter_manifest())
  fake.bundle.val = Some(bundle)
  (h, bundle)
}

///|
test "bundle mounts into a live app and dispatches through stock machinery" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  inspect(h.find_all(".counter").length(), content="0")
  guard bundle.make_instance("Counter", args={ "count": Num(10) })
    is Some(inst0)

  // seeding the instance is a plain state change
  h.send_at_root("setSlot", args=[inst0.to_value()])
  inspect(h.text(".count"), content="10")
  inspect(h.text(".label"), content="count is 10")

  // input dispatch: guest returns a successor handle -> new DynObj -> render;
  // right after the click the OLD instance is queued but not yet dropped
  h.click(".inc")
  inspect(h.text(".count"), content="11")
  assert_true(fake.counters.get(inst0.handle()) is Some(10.0))
  assert_true(superseded_count() > 0)

  // the NEXT dispatch collects it (one-transaction delay)
  h.click(".dec")
  inspect(h.text(".count"), content="10")
  assert_true(fake.counters.get(inst0.handle()) is None)

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
test "guest request round-trips through a host RequestFn" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  h.app.scope.register_request_handlers({
    "double": RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("bad args")))
      }
    }),
  })
  guard bundle.make_instance("Counter", args={ "count": Num(21) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  inspect(h.text(".count"), content="21")
  // input "double" fires ctx.request; the response dispatches the guest's
  // response bucket handler, which returns the doubled successor
  h.click(".double")
  inspect(h.text(".count"), content="42")
}

///|
test "nested guest children render and dispatch through two DynObj levels" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard bundle.make_instance("Pair") is Some(pair)
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
  guard bundle.make_instance("Counter", args={ "count": Num(5) }) is Some(c)
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
test "host @each iterates a guest instance via seq-entries" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (h, bundle) = mount_with_bundle(fake)
  guard bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(c)
  h.send_at_root("setSlot", args=[c.to_value()])
  debug_inspect(h.texts("li"), content="[\"10\"]")
  h.click(".inc")
  debug_inspect(h.texts("li"), content="[\"11\"]")
}

///|
test "migrate_instance rebuilds state from the JSON projection" {
  collect_superseded()
  let fake = FakeGuest::new()
  let (_h, bundle) = mount_with_bundle(fake)
  guard bundle.make_instance("Counter", args={ "count": Num(10) }) is Some(a)
  guard bundle.migrate_instance(a.to_value(), "Counter") is Some(b)
  assert_true(a.handle() != b.handle())
  assert_true(fake.counters.get(b.handle()) is Some(10.0))
  // non-guest values don't migrate
  assert_true(bundle.migrate_instance(Str("nope"), "Counter") is None)
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
  // the shell itself has no DOM handlers; the guest's views add click
  assert_false(h.app.event_names().contains("click"))
  let _ = register_bundle(h.app.scope, FakeGuest::new(), counter_manifest())
  assert_true(h.app.event_names().contains("click"))
}

///|
test "component_names lists the manifest's components in order" {
  let (_, bundle) = mount_with_bundle(FakeGuest::new())
  debug_inspect(bundle.component_names(), content="[\"Counter\", \"Pair\"]")
}

///|
test "manifest parses from the bridge's JSON projection" {
  let json =
    #|{"apiVersion": 1, "moduleName": "counterlib", "components": [
    #|  {"name": "Counter",
    #|   "views": [{"name": "main", "html": "<div>{.count}</div>"}],
    #|   "inputHandlers": ["inc"], "receiveHandlers": [],
    #|   "responseHandlers": [], "methodNames": [], "style": ""}]}
  let m = DynManifest::from_json_string(json)
  inspect(m.module_name, content="counterlib")
  debug_inspect(m.components[0].input_handlers, content="[\"inc\"]")
  inspect(m.components[0].views[0].html, content="<div>{.count}</div>")
}

///|
test "manifest with wrong api version is rejected" {
  let bad =
    #|{"apiVersion": 2, "moduleName": "x", "components": []}
  let mut failed = false
  let _ = DynManifest::from_json_string(bad) catch {
    _ => {
      failed = true
      { api_version: 0, module_name: "", components: [] }
    }
  }
  assert_true(failed)
}
