// The `@loop-with` protocol as it crosses the Fn boundary, both directions in
// one file.
//
// A `@loop-with` handler is reached through `Obj::obj_callable`, which — like
// every seam below the component layer — speaks `Value`. So the typed `LoopCtx`
// the renderer builds travels as a Map of Fn-convention closures, and the typed
// `LoopWith` the handler returns travels as a Map of four optional entries.
//
// Both encodings used to be written HALF here and half in `render/loop.mbt`,
// which meant six string keys ("iterData", "start", "end", "keys", "lookup",
// "filter") that two packages had to agree on with nothing checking, and a
// `LoopPlan` in the renderer that was `LoopWith` again with one field made
// non-optional. Encode and decode sit next to each other now: change a key and
// both sides move together, or neither compiles.

///|
/// Encode into the `{ iterData?, start?, end?, keys? }` Map a handler's return
/// crosses as. An absent part contributes no entry — "the handler did not
/// slice" and "the handler sliced to nothing" are different answers.
pub fn LoopWith::to_value(self : LoopWith) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = Map([])
  match self.iter_data {
    Some(v) => m["iterData"] = v
    None => ()
  }
  match self.start {
    Some(i) => m["start"] = Num(i.to_double())
    None => ()
  }
  match self.end {
    Some(i) => m["end"] = Num(i.to_double())
    None => ()
  }
  match self.keys {
    Some(ks) => m["keys"] = List(ks)
    None => ()
  }
  Map(m)
}

///|
/// Read one back. Each part goes through a PARTIAL coercer, so a missing entry
/// and a wrong-shaped one both read as absent rather than as a zero; a result
/// that is not a Map at all reads as all-absent through the same calls.
///
/// `seq` supplies the `iter_data` default (`{ seq }`, the JS shape), so a
/// handler that only sliced still hands `@when` / `@enrich-with` something to
/// read — and the renderer's no-`@loop-with` path builds the same default
/// through `LoopWith::new`.
pub fn LoopWith::of_value(v : @tutuca.Value, seq : @tutuca.Value) -> LoopWith {
  {
    iter_data: Some(v.field_opt("iterData").unwrap_or(Map({ "seq": seq }))),
    start: v.field("start").int_opt(),
    end: v.field("end").int_opt(),
    keys: v.field("keys").list_opt(),
  }
}

///|
/// Encode the loop context: two Fn-convention closures under the names the
/// decode below reads.
pub fn LoopCtx::to_value(self : LoopCtx) -> @tutuca.Value {
  Map({
    "lookup": Fn(args => {
      match args {
        [_, Str(name), ..] => (self.lookup)(name)
        _ => Null
      }
    }),
    "filter": Fn(args => {
      match args {
        [_, k, v, idata, ..] => Bool((self.filter)(k, v, idata))
        _ => Bool(true)
      }
    }),
  })
}

///|
/// Read one back into the typed `LoopCtx` a `@loop-with` handler receives.
/// A missing or wrong-shaped entry degrades to the neutral answer: `lookup`
/// finds nothing, `filter` keeps the item.
pub fn LoopCtx::of_value(v : @tutuca.Value) -> LoopCtx {
  {
    lookup: name => v.field("lookup").call([Str(name)]),
    filter: (k, item, iter) => {
      v.field("filter").call([k, item, iter]).is_truthy()
    },
  }
}
