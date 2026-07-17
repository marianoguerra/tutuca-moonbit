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
impl DynComponent for Counter with fn handle(self, bucket, name, _event, args) {
  match (bucket, name) {
    (INPUT, "inc") => Some(self.next(self.count + 1.0) as &DynComponent)
    (INPUT, "dec") => Some(self.next(self.count - 1.0) as &DynComponent)
    // fire a host-side request; the response arrives below
    (INPUT, "double") => {
      @control.request("double", [@values.Value::Number(self.count)])
      None
    }
    (RESPONSE, "double") =>
      match args {
        // response args are [result, error]
        [@values.Value::Number(n), ..] =>
          Some(self.next(n) as &DynComponent)
        _ => None
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
impl DynComponent for Counter with fn call_method(self, name, _args) {
  match name {
    "label" => @values.Value::Text("count is \{self.count}")
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Counter with fn with_field(self, name, v) {
  match (name, v) {
    ("count", @values.Value::Number(n)) =>
      Some(self.next(n) as &DynComponent)
    _ => None
  }
}

///|
impl DynComponent for Counter with fn to_json(self) {
  let hist = self.history.map(n => n.to_string()).join(", ")
  "{\"count\": \{self.count}, \"history\": [\{hist}]}"
}

///|
fn make_counter(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut count = 0.0
  let history = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("count", @values.Value::Number(n)) => count = n
      // hot-swap migration hands the to-json projection back as args
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
  {
    name: "Counter",
    views: [
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
          #|    <button class="btn btn-sm btn-secondary double" @on.click="double">double</button>
          #|    <span class="text-sm opacity-70 label" @text="$label"></span>
          #|    <ul class="flex gap-1 flex-wrap history"><li class="badge badge-sm badge-ghost" @each=".history" @text="@value"></li></ul>
          #|  </div>
          #|</div>
        ),
      },
    ],
    input_handlers: ["inc", "dec", "double"],
    receive_handlers: ["init", "sum"],
    response_handlers: ["double"],
    method_names: ["label"],
    // styling is entirely margaui (daisyUI) classes above; the universal demo
    // compiles them, so no scoped fallback CSS
    style: "",
  }
}

///| Two nested child Counters, created through control.make-instance and
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
impl DynComponent for Pair with fn to_json(self) {
  "{\"left\": \{self.left}, \"right\": \{self.right}}"
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
  {
    name: "Pair",
    views: [
      {
        name: "main",
        html: (
          #|<div class="flex flex-col gap-2 pair">
          #|  <div class="left"><x render=".left"></div>
          #|  <div class="right"><x render=".right"></div>
          #|</div>
        ),
      },
    ],
    input_handlers: [],
    receive_handlers: ["init"],
    response_handlers: [],
    method_names: [],
    style: "",
  }
}

///|
fn dyn_module() -> DynModule {
  {
    name: "counterlib",
    components: [
      { def: counter_def(), make: make_counter },
      { def: pair_def(), make: make_pair },
    ],
  }
}
