///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The counter guest module: opaque native state + tutuca view strings.
/// Exercises the whole `tutuca:component` surface: lazy field reads, list
/// fields (host `@each`), a view method (`$label`), a request round trip
/// (input "double" -> control.request -> response "double"), and nested
/// same-bundle children (Pair holds two Counters via control.make-instance
/// tokens). Everything an author writes is in this file; sdk.mbt does the
/// rest.

///|
priv struct Counter {
  count : Double
  history : Array[Double]
}

///|
fn Counter::next(self : Counter, count : Double) -> Counter {
  let history = self.history.copy()
  history.push(self.count)
  { count, history }
}

///|
impl DynComponent for Counter with fn get_field(self, name) {
  match name {
    "count" => Some(@values.Value::Number(self.count))
    "history" => {
      let h = @values.list_new()
      for n in self.history {
        @values.list_push(h, @values.Value::Number(n))
      }
      Some(@values.Value::List(h))
    }
    _ => None
  }
}

///|
impl DynComponent for Counter with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    (INPUT, "inc") => Some(self.next(self.count + 1.0) as &DynComponent)
    (INPUT, "dec") => Some(self.next(self.count - 1.0) as &DynComponent)
    // a request the HOST serves; `on_ok` routes the answer to a handler of
    // its own, which then carries just the value instead of [result, error]
    (INPUT, "double") => {
      @control.request("double", [@values.Value::Number(self.count)], {
        on_ok: Some("doubled"),
        on_error: None,
        on_res: None,
        live_path: false,
      })
      None
    }
    (RESPONSE, "doubled") =>
      match args {
        [@values.Value::Number(n), ..] => Some(self.next(n) as &DynComponent)
        _ => None
      }
    // a request this BUNDLE serves (dyn_module's `serve`), which its own
    // components find before any host handler of the same name
    (INPUT, "triple") => {
      @control.request("triple", [@values.Value::Number(self.count)], {
        on_ok: None,
        on_error: None,
        on_res: None,
        live_path: false,
      })
      None
    }
    (RESPONSE, "triple") =>
      match args {
        // no on_ok: response args are [result, error]
        [@values.Value::Number(n), ..] => Some(self.next(n) as &DynComponent)
        _ => None
      }
    // tell whoever is above: a Pair parent hears this, and so would the host
    (INPUT, "announce") => {
      @control.emit("counted", [@values.Value::Number(self.count)])
      None
    }
    // boundary exercise: sum a host list of numbers (guest -> values import)
    (RECEIVE, "sum") =>
      match args {
        [@values.Value::List(h)] => {
          let mut total = 0.0
          let len = @values.list_len(h)
          for i in 0U..<len {
            match @values.list_get(h, i) {
              @values.Value::Number(n) => total += n
              _ => ()
            }
          }
          Some(self.next(total) as &DynComponent)
        }
        _ => None
      }
    (RECEIVE, "init") => None
    _ => None
  }
}

///|
/// Iterated by host `@each` over the instance itself (obj_seq_entries).
impl DynComponent for Counter with fn seq_entries(self) {
  let out = []
  for i, n in self.history {
    out.push(("h\{i}", @values.Value::Number(n)))
  }
  Some(out)
}

///|
impl DynComponent for Counter with fn call_method(self, name, args) {
  match name {
    "label" => @values.Value::Text("count is \{self.count}")
    // a `@when` filter over the history: called with (key, item, iter-data),
    // answered as a boolean — the zero the counter started at is not worth a
    // badge of its own
    "nonZero" =>
      match args {
        [_, @values.Value::Number(v), ..] => @values.Value::Boolean(v != 0.0)
        _ => @values.Value::Boolean(true)
      }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Counter with fn with_field(self, name, v) {
  match (name, v) {
    ("count", @values.Value::Number(n)) => Some(self.next(n) as &DynComponent)
    _ => None
  }
}

///|
fn make_counter(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut count = 0.0
  let history = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("count", @values.Value::Number(n)) => count = n
      // hot-swap migration hands the declared fields back as args
      ("history", @values.Value::List(h)) =>
        for i in 0U..<@values.list_len(h) {
          match @values.list_get(h, i) {
            @values.Value::Number(n) => history.push(n)
            _ => ()
          }
        }
      _ => ()
    }
  }
  let c : Counter = { count, history }
  c as &DynComponent
}

///|
fn counter_def() -> ComponentDef {
  component_def(
    "Counter",
    doc="A number with buttons that raise and lower it, keeping every value it has held.",
    keywords=["counter", "number", "tally", "increment"],
    category="input",
    message_docs=[
      { name: "inc", doc: "Add one." },
      { name: "dec", doc: "Subtract one." },
      { name: "double", doc: "Ask the host to double the count." },
      { name: "triple", doc: "Ask this bundle to triple the count." },
      { name: "announce", doc: "Tell the parent what the count is now." },
      { name: "sum", doc: "Replace the count with the sum of a list." },
      { name: "label", doc: "The count as a sentence, for a view." },
    ],
    views=[
      {
        name: "main",
        html: (
          #|<div class="card bg-base-100 border border-base-300 shadow-sm counter">
          #|  <div class="card-body gap-2 items-center p-4">
          #|    <div class="join">
          #|      <button class="btn btn-sm join-item dec" @on.click="dec">−</button>
          #|      <span class="btn btn-sm join-item no-animation pointer-events-none count" @text=".count"></span>
          #|      <button class="btn btn-sm join-item inc" @on.click="inc">+</button>
          #|    </div>
          #|    <div class="join">
          #|      <button class="btn btn-sm btn-secondary join-item double" @on.click="double">double</button>
          #|      <button class="btn btn-sm btn-secondary join-item triple" @on.click="triple">triple</button>
          #|      <button class="btn btn-sm btn-ghost join-item announce" @on.click="announce">announce</button>
          #|    </div>
          #|    <span class="text-sm opacity-70 label" @text="$label"></span>
          #|    <ul class="flex gap-1 flex-wrap history"><li class="badge badge-sm badge-ghost" @each=".history" @when="nonZero" @text="@value"></li></ul>
          #|  </div>
          #|</div>
        ),
      },
    ],
    // The state this component holds. Declaring it is what gives the host the
    // JSON projection, structural equality and the generated `setCount` /
    // `pushInHistory` mutators — none of which is implemented below. The docs
    // and the constraint are the half a TYPE cannot state, and they are what a
    // generated form and a catalog search read.
    types=[
      { kind: TY_FLOAT, elem: None, items: [], name: "", members: [] },
      { kind: TY_LIST, elem: Some(0), items: [], name: "", members: [] },
    ],
    fields=[
      field(
        "count",
        0,
        doc="The current value.",
        required=false,
        constraint=Some({ ..no_limits(), min: Some(-1000), max: Some(1000) }),
      ),
      field("history", 1, doc="Every value the count has held, oldest first."),
    ],
    // `setCount` is deliberately NOT here: it is the mutator `count` implies,
    // and the host answers it — declaring it would take it back.
    handlers=["inc", "dec", "double", "triple", "announce"],
    receives=["init", "sum"],
    responses=["doubled", "triple"],
    methods=["label"],
    whens=["nonZero"],
    // a named initial state a host can offer instead of the bare constructor
    inits=[
      {
        name: "with-history",
        args_json: "{\"count\": 3, \"history\": [0, 1, 2]}",
        doc: "Starts at three, with the first three counts already behind it.",
      },
    ],
    // styling is entirely margaui (daisyUI) classes above; the universal demo
    // compiles them, so no scoped fallback CSS — and under the host's strict
    // tier an empty `style` is the only thing a bundle may ship.
  )
}

///|
/// Two nested child Counters, created through control.make-instance and
/// exposed as instance-token fields the host renders with <x render>.
priv struct Pair {
  left : UInt64
  right : UInt64
}

///|
impl DynComponent for Pair with fn get_field(self, name) {
  match name {
    "left" => Some(@values.Value::Instance(self.left))
    "right" => Some(@values.Value::Instance(self.right))
    _ => None
  }
}

///|
impl DynComponent for Pair with fn handle(self, bucket, name, _args) {
  match (bucket, name) {
    // a child announced itself: swap the two, and keep the bubble from
    // travelling further up (the host would hear it otherwise)
    (BUBBLE, "counted") => {
      @control.stop_propagation()
      Some({ left: self.right, right: self.left } as &DynComponent)
    }
    // reach INTO this component's own subtree: `.left` is the child the left
    // field holds, and "sum" is its receive handler
    (INPUT, "zeroLeft") => {
      @control.send_at([@control.PathStep::Field("left")], "sum", [
        @values.Value::List(@values.list_new()),
      ])
      None
    }
    _ => None
  }
}

///|
impl DynComponent for Pair with fn with_field(self, name, v) {
  match (name, v) {
    ("left", @values.Value::Instance(t)) => {
      let p : Pair = { left: t, right: self.right }
      Some(p as &DynComponent)
    }
    ("right", @values.Value::Instance(t)) => {
      let p : Pair = { left: self.left, right: t }
      Some(p as &DynComponent)
    }
    _ => None
  }
}

///|
fn make_pair(_args : Array[(String, @values.Value)]) -> &DynComponent {
  let left = @control.make_instance("Counter", [
    ("count", @values.Value::Number(1)),
  ])
  let right = @control.make_instance("Counter", [
    ("count", @values.Value::Number(100)),
  ])
  let p : Pair = { left, right }
  p as &DynComponent
}

///|
fn pair_def() -> ComponentDef {
  component_def(
    "Pair",
    doc="Two counters side by side; announcing from either one swaps them.",
    keywords=["counter", "pair", "layout"],
    category="layout",
    message_docs=[
      { name: "zeroLeft", doc: "Set the left counter back to zero." },
      { name: "counted", doc: "A child counter announced its value." },
      { name: "triple", doc: "Triple a number (served by this bundle)." },
    ],
    views=[
      {
        name: "main",
        html: (
          #|<div class="flex flex-col gap-2 pair">
          #|  <button class="btn btn-xs btn-ghost self-start zeroleft" @on.click="zeroLeft">zero the left one</button>
          #|  <div class="left"><x render=".left"></div>
          #|  <div class="right"><x render=".right"></div>
          #|</div>
        ),
      },
    ],
    // both children are Counters from this same module, held as instance
    // tokens (control.make-instance) — a `component` slot to the host
    types=[
      { kind: TY_COMP, elem: None, items: [], name: "Counter", members: [] },
    ],
    fields=[
      field("left", 0, doc="The counter on the left.", required=true),
      field("right", 0, doc="The counter on the right.", required=true),
    ],
    handlers=["zeroLeft"],
    receives=["init"],
    // what its children raise with control.emit
    bubbles=["counted"],
    // the bundle serves this one itself; a host handler of the same name
    // would only be reached if this bundle did not declare it
    requests=["triple"],
  )
}

///|
/// The bundle's own request handlers, which its components reach before any
/// host handler of the same name (see `pair_def`'s `requests`).
fn serve_request(name : String, args : Array[@values.Value]) -> RequestResult {
  match (name, args) {
    ("triple", [@values.Value::Number(n), ..]) =>
      RequestResult::Ok(@values.Value::Number(n * 3.0))
    _ =>
      RequestResult::Err(@values.Value::Text("counterlib: no request \{name}"))
  }
}

///|
fn dyn_module() -> DynModule {
  module_def(
    "counterlib",
    [
      { def: counter_def(), make: make_counter },
      { def: pair_def(), make: make_pair },
    ],
    // the bundle's own request service (WIT handle-request)
    serve=serve_request,
    doc="Sample counters — the reference bundle for the tutuca:component contract.",
    version="0.3.0",
    // It asks for nothing: no clock, no randomness, no timer. That is what
    // most components need, and it is what makes this one trivially safe to
    // mount from anywhere.
    capabilities=[],
  )
}
