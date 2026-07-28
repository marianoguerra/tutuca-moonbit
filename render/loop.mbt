// @loop-with plumbing (JS renderer.js makeLoopCtx / unpackLoopResult /
// normalizeRange): the handler receives (seq, loopCtx) with the component as
// `this` and returns { iterData?, start?, end?, keys? } — iterData flows to
// @when/@enrich-with, start/end slice the iteration, an explicit keys list
// takes over ordering entirely (skipping @when).

///|
/// The plan for one `@loop-with` loop: the handler is called with
/// `(seq, loopCtx)` and the component as `this`, and its return decodes
/// through `@component.LoopWith` — the ONE place that encoding is written
/// (see component/loop_codec.mbt). The renderer used to keep a `LoopPlan`
/// of its own here, which was `LoopWith` again, filled by a decoder that had
/// to guess the same four key names the encoder chose.
fn loop_plan(
  stack : RenderStack,
  seq : @tutuca.Value,
  filter_h : @tutuca.Value?,
  loop_with_val : @tutuca.Val?,
) -> @component.LoopWith {
  guard loop_with_val is Some(lv) else {
    return @component.LoopWith::new(iter_data=Map({ "seq": seq }))
  }
  let ctx : @component.LoopCtx = {
    lookup: name => @tutuca.Stack::lookup_bind(stack, name),
    filter: (k, v, idata) => {
      match filter_h {
        Some(f) => call_handler(f, stack.it, [k, v, idata]).is_truthy()
        None => true
      }
    },
  }
  let h = lv.eval_as_handler(stack)
  @component.LoopWith::of_value(
    call_handler(h, stack.it, [seq, ctx.to_value()]),
    seq,
  )
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
  loop_plan(stack, seq, filter_h, loop_with_val).iter_data.unwrap_or(Null)
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
