// Stack rebuild: replay the frames
// the renderer pushed while rendering down a path, so a handler runs with
// the binds (`@key`, `@value`, @enrich-with scopes) its element saw. The
// frame shapes MUST mirror render()'s enter calls exactly:
//
//   render context            renderer                       rebuild
//   component boundary        enter(value, {})               FieldStep / SeqAccessStep
//   keyed component           enter(value, {key})            SeqStep
//   iterated render target    item scope + enter(value, {})  EachRenderItStep
//   @each item (no comp)      enter(value, binds, false)     FrameBind::Each
//   loop-less @enrich-with    enter(it, binds, false)        FrameBind::Scope
//
// The first three ADDRESS something and are steps; the last two do not and are
// binds carried beside the frame's items, each knowing how many items came
// before it. `build_dispatch_stack` interleaves the two in that order, which is
// the order the renderer entered them.

///|
/// Rebuild the per-item binds for `key`, mirroring render_each: seed
/// {key, value}, run @enrich-with against the iterData that @loop-with
/// supplies (via loop_iter_data below), then restore the protected binds.
fn each_binds(
  stack : RenderStack,
  val : @tutuca.Val,
  when_val : @tutuca.Val?,
  enrich_with_val : @tutuca.Val?,
  loop_with_val : @tutuca.Val?,
  key : @tutuca.PathKey,
) -> Map[String, @tutuca.Value] {
  let seq = val.eval(stack)
  let k = key.to_value()
  // One lookup for List, Map and a custom-collection Obj alike (@tutuca).
  let value = seq.item(key)
  let binds : Map[String, @tutuca.Value] = { "key": k, "value": value }
  match enrich_with_val {
    Some(ev) => {
      // mirror the renderer's enrichment: @loop-with (if any)
      // supplies the iterData the enricher sees
      let iter_data = loop_iter_data(stack, seq, when_val, loop_with_val)
      let enricher = ev.eval_as_handler(stack)
      call_handler(enricher, stack.it, [Map(binds), k, value, iter_data])
      |> ignore
      binds["key"] = k
      binds["value"] = value
    }
    None => ()
  }
  binds
}

///|
fn step_enter_frame(
  step : @tutuca.Step,
  stack : RenderStack,
  next : @tutuca.Value,
  render_path : @tutuca.DispatchPath,
) -> RenderStack {
  match step {
    // component boundary: clean frame on the entered value
    FieldStep(_) | SeqAccessStep(..) => stack.enter(next, Map([]), render_path~)
    SeqStep(field=_, key~) =>
      stack.enter(next, { "key": key.to_value() }, render_path~)
    // iterated render target: the @each item scope, then the component frame
    EachRenderItStep(field=_, key~) =>
      stack
      .enter(
        next,
        { "key": key.to_value(), "value": next },
        is_frame=false,
        render_path~,
      )
      .enter(next, Map([]), render_path~)
  }
}

///|
/// Enter the scope one `FrameBind` opened.
///
/// It addresses nothing, so `it` is unchanged and the frame is not a component
/// boundary — what it contributes is BINDS, computed here rather than carried,
/// so a rebuild sees the state as it is now.
fn bind_enter_frame(
  bind : @tutuca.FrameBind,
  stack : RenderStack,
  render_path : @tutuca.DispatchPath,
) -> RenderStack {
  match bind {
    // re-evaluate the @enrich-with handler against the rebuilt stack so
    // its custom binds are present
    Scope(val~) => {
      let handler = val.eval_as_handler(stack)
      let binds : Map[String, @tutuca.Value] = match
        call_handler(handler, stack.it, []) {
        Map(m) => m
        _ => Map([])
      }
      stack.enter(stack.it, binds, is_frame=false, render_path~)
    }
    // The binds carry the item; `it` stays the component.
    Each(val~, when_val~, enrich_with_val~, loop_with_val~, key~) =>
      stack.enter(
        stack.it,
        each_binds(stack, val, when_val, enrich_with_val, loop_with_val, key),
        is_frame=false,
        render_path~,
      )
  }
}

///|
pub fn build_stack(path : @tutuca.Path, stack : RenderStack) -> RenderStack? {
  let mut st = stack
  let mut render_path = stack.render_path
  for step in path.steps {
    guard @tutuca.step_get(st.it, step) is Some(next) else { // bad path item (warn and return null)
      return None
    }
    render_path = render_path.concat([step])
    st = step_enter_frame(step, st, next, render_path)
  }
  Some(st)
}

///|
pub fn build_dispatch_stack(
  path : @tutuca.DispatchPath,
  stack : RenderStack,
) -> RenderStack? {
  let mut st = stack
  let mut render_path = @tutuca.DispatchPath::new()
  for frame_index, frame in path.frames {
    if frame_index > 0 || !frame.base.steps.is_empty() {
      render_path = render_path.push_frame(frame.base)
      guard frame.base.lookup(stack.root) is Some(base_value) else {
        return None
      }
      st = st.enter(base_value, Map([]), render_path~, pending_frame=false)
    }
    // Items and binds, interleaved in the order the renderer entered them: a
    // bind carries the number of items that preceded it, so the ones due
    // before item `i` are exactly those indexed `i`.
    fn enter_binds_at(
      st : RenderStack,
      render_path : @tutuca.DispatchPath,
      at : Int,
    ) -> (RenderStack, @tutuca.DispatchPath) {
      let mut st = st
      let mut render_path = render_path
      for pair in frame.binds {
        if pair.0 == at {
          render_path = render_path.push_bind(pair.1)
          st = bind_enter_frame(pair.1, st, render_path)
        }
      }
      (st, render_path)
    }

    for i, item in frame.items {
      let (st2, rp2) = enter_binds_at(st, render_path, i)
      st = st2
      render_path = rp2
      let Plain(step~, ..) = item
      guard @tutuca.step_get(st.it, step) is Some(next) else { return None }
      render_path = render_path.push_item(item)
      st = step_enter_frame(step, st, next, render_path)
    }
    let (st3, rp3) = enter_binds_at(st, render_path, frame.items.length())
    st = st3
    render_path = rp3
  }
  Some(st)
}
