// @loop-with plumbing (JS renderer.js makeLoopCtx / unpackLoopResult /
// normalizeRange): the handler receives (seq, loopCtx) with the component as
// `this` and returns { iterData?, start?, end?, keys? } — iterData flows to
// @when/@enrich-with, start/end slice the iteration, an explicit keys list
// takes over ordering entirely (skipping @when).

///|
priv struct LoopPlan {
  iter_data : @tutuca.Value
  start : Int?
  end : Int?
  keys : Array[@tutuca.Value]?
}

///|
/// The loopCtx handed to the @loop-with handler: `lookup` reads `@name`
/// binds, `filter` applies the loop's own @when (both under the Fn
/// convention — element 0 is the this-slot).
fn make_loop_ctx(
  stack : RenderStack,
  filter_h : @tutuca.Value?,
) -> @tutuca.Value {
  Map({
    "lookup": Fn(args => {
      match args {
        [_, Str(name), ..] => @tutuca.Stack::lookup_bind(stack, name)
        _ => Null
      }
    }),
    "filter": Fn(args => {
      match args {
        [_, k, v, idata, ..] =>
          match filter_h {
            Some(f) => call_handler(f, stack.it, [k, v, idata])
            None => Bool(true)
          }
        _ => Bool(true)
      }
    }),
  })
}

///|
fn unpack_loop_result(result : @tutuca.Value, seq : @tutuca.Value) -> LoopPlan {
  let dflt : @tutuca.Value = Map({ "seq": seq })
  match result {
    Map(m) => {
      let iter_data = m.get("iterData").unwrap_or(dflt)
      let start : Int? = match m.get("start") {
        Some(Num(n)) => Some(n.to_int())
        _ => None
      }
      let end : Int? = match m.get("end") {
        Some(Num(n)) => Some(n.to_int())
        _ => None
      }
      let keys : Array[@tutuca.Value]? = match m.get("keys") {
        Some(List(a)) => Some(a)
        _ => None
      }
      { iter_data, start, end, keys }
    }
    _ => { iter_data: dflt, start: None, end: None, keys: None }
  }
}

///|
fn loop_plan(
  stack : RenderStack,
  seq : @tutuca.Value,
  filter_h : @tutuca.Value?,
  loop_with_val : @tutuca.Val?,
) -> LoopPlan {
  match loop_with_val {
    Some(lv) => {
      let h = lv.eval_as_handler(stack)
      unpack_loop_result(
        call_handler(h, stack.it, [seq, make_loop_ctx(stack, filter_h)]),
        seq,
      )
    }
    None =>
      { iter_data: Map({ "seq": seq }), start: None, end: None, keys: None }
  }
}

///|
/// The iterData an @enrich-with sees — SHARED by render_each and the stack
/// rebuild's each_binds so the two stay mirrored (JS IterInfo.enrichBinds).
fn loop_iter_data(
  stack : RenderStack,
  seq : @tutuca.Value,
  when_val : @tutuca.Val?,
  loop_with_val : @tutuca.Val?,
) -> @tutuca.Value {
  let filter_h : @tutuca.Value? = match when_val {
    Some(v) => Some(v.eval_as_handler(stack))
    None => None
  }
  loop_plan(stack, seq, filter_h, loop_with_val).iter_data
}

///|
/// JS Array.slice index semantics: negatives count from the end, clamped.
fn normalize_range(start : Int?, end : Int?, size : Int) -> (Int, Int) {
  fn norm(i : Int) -> Int {
    if i < 0 {
      if size + i > 0 {
        size + i
      } else {
        0
      }
    } else if i > size {
      size
    } else {
      i
    }
  }

  (norm(start.unwrap_or(0)), norm(end.unwrap_or(size)))
}
