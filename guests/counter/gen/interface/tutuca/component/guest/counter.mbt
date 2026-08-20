///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The counter guest behavior: opaque native state behind static views.
/// Exercises the whole `tutuca:component` surface: lazy field reads, list
/// fields (host `@each`), a view method (`$label`), a request round trip
/// (input "double" -> control.request -> response "double"), and nested
/// same-bundle children (Pair holds two Counters via control.make-instance
/// tokens). The declaration and views live in manifest.json and views/;
/// sdk.mbt handles the generated ABI declarations.

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
    (RECEIVE, "inc") => Changed(self.next(self.count + 1.0) as &DynComponent)
    (RECEIVE, "dec") => Changed(self.next(self.count - 1.0) as &DynComponent)
    // a request the HOST serves; `on_ok` routes the answer to a handler of
    // its own, which then carries just the value instead of [result, error]
    (RECEIVE, "double") => {
      @control.intent("double", [@values.Value::Number(self.count)], {
        route: [LEX],
        on_ok: Some("doubled"),
        on_error: None,
        on_unhandled: None,
        live_path: false,
      })
      Unchanged
    }
    (RECEIVE, "doubled") =>
      match args {
        [@values.Value::Number(n), ..] => Changed(self.next(n) as &DynComponent)
        _ => Unchanged
      }
    // an intent this BUNDLE serves (dyn_module's `serve`), which its own
    // components reach before any host handler of the same name.
    //
    // The ANSWER is named `tripled`, not `triple`. One bucket holds both the
    // click and the answer, so reusing the name would collide: the first arm
    // would take the answer and dispatch the intent all over again.
    (RECEIVE, "triple") => {
      @control.intent("triple", [@values.Value::Number(self.count)], {
        route: [LEX],
        on_ok: Some("tripled"),
        on_error: None,
        on_unhandled: None,
        live_path: false,
      })
      Unchanged
    }
    (RECEIVE, "tripled") =>
      match args {
        [@values.Value::Number(n), ..] => Changed(self.next(n) as &DynComponent)
        _ => Unchanged
      }
    // tell whoever is above: a Pair parent hears this, and so would the host
    (RECEIVE, "announce") => {
      @control.intent("counted", [@values.Value::Number(self.count)], {
        route: [DYN],
        on_ok: None,
        on_error: None,
        on_unhandled: None,
        live_path: false,
      })
      Unchanged
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
          Changed(self.next(total) as &DynComponent)
        }
        _ => Unchanged
      }
    (RECEIVE, "init") => Unchanged
    _ => Unhandled
  }
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
    (INTENT, "counted") => {
      @control.stop_propagation()
      Changed({ left: self.right, right: self.left } as &DynComponent)
    }
    // reach INTO this component's own subtree: `.left` is the child the left
    // field holds, and "sum" is its receive handler
    (RECEIVE, "zeroLeft") => {
      @control.send_at([@control.PathStep::Field("left")], "sum", [
        @values.Value::List(@values.list_new()),
      ])
      Unchanged
    }
    _ => Unhandled
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
/// The bundle's own request handlers, which its components reach before any
/// host handler of the same name (the static manifest declares `requests`).
fn serve_intent_impl(name : String, args : Array[@values.Value]) -> ServeResult {
  match (name, args) {
    ("triple", [@values.Value::Number(n), ..]) =>
      ServeResult::Ok(@values.Value::Number(n * 3.0))
    _ =>
      ServeResult::Err(@values.Value::Text("counterlib: no service \{name}"))
  }
}

///|
fn dyn_module() -> DynModule {
  module_def(
    // Neither component persists, which is the OTHER half of the persistence
    // contract worth showing: their state is exactly the fields they declare,
    // so the host projects and rebuilds them itself and a `persist` here would
    // be that list written twice.
    [dyn_comp("Counter", make_counter), dyn_comp("Pair", make_pair)],
    // the bundle's own request service (WIT handle-request)
    serve=serve_intent_impl,
  )
}
