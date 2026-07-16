// Stack rebuild (JS Path.buildStack + Step.enterFrame): replay the frames
// the renderer pushed while rendering down a path, so a handler runs with
// the binds (`@key`, `@value`, @enrich-with scopes) its element saw. The
// frame shapes MUST mirror render()'s enter calls exactly:
//
//   render context            renderer                       rebuild step
//   component boundary        enter(value, {})               FieldStep / SeqAccessStep
//   keyed component           enter(value, {key})            SeqStep
//   iterated render target    item scope + enter(value, {})  EachRenderItStep
//   @each item (no comp)      enter(value, binds, false)     EachBindStep
//   loop-less @enrich-with    enter(it, binds, false)        ScopeBindStep
//   generic scope             enter(it, binds, false)        BindStep

///|
fn key_value(k : @tutuca.PathKey) -> @tutuca.Value {
  match k {
    KInt(i) => Num(i.to_double())
    KStr(s) => Str(s)
  }
}

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
  let k = key_value(key)
  let value : @tutuca.Value = match (seq, key) {
    (Map(m), KStr(s)) => m.get(s).unwrap_or(Null)
    (List(a), KInt(i)) => if i >= 0 && i < a.length() { a[i] } else { Null }
    // custom seq (JS SEQ_INFO): resolve the item through obj_item
    (Obj(o), k) => o.obj_item(k).unwrap_or(Null)
    _ => Null
  }
  let binds : Map[String, @tutuca.Value] = { "key": k, "value": value }
  match enrich_with_val {
    Some(ev) => {
      // mirror renderer + JS IterInfo.enrichBinds: @loop-with (if any)
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
) -> RenderStack {
  match step {
    // component boundary: clean frame on the entered value
    FieldStep(_) | SeqAccessStep(..) => stack.enter(next, {})
    SeqStep(field=_, key~) => stack.enter(next, { "key": key_value(key) })
    // iterated render target: the @each item scope, then the component frame
    EachRenderItStep(field=_, key~) =>
      stack
      .enter(next, { "key": key_value(key), "value": next }, is_frame=false)
      .enter(next, {})
    BindStep(binds~) => stack.enter(next, binds.copy(), is_frame=false)
    ScopeBindStep(val~) => {
      // re-evaluate the @enrich-with handler against the rebuilt stack so
      // its custom binds are present (JS ScopeBindStep.enterFrame)
      let handler = val.eval_as_handler(stack)
      let binds : Map[String, @tutuca.Value] = match
        call_handler(handler, stack.it, []) {
        Map(m) => m
        _ => {}
      }
      stack.enter(next, binds, is_frame=false)
    }
    // `next` is the pass-through component value (JS EachBindStep.lookup
    // returns v): binds carry the item, `it` stays the component
    EachBindStep(val~, when_val~, enrich_with_val~, loop_with_val~, key~) =>
      stack.enter(
        next,
        each_binds(stack, val, when_val, enrich_with_val, loop_with_val, key),
        is_frame=false,
      )
  }
}

///|
pub fn build_stack(path : @tutuca.Path, stack : RenderStack) -> RenderStack? {
  let mut st = stack
  for step in path.steps {
    let prev_node : &@tutuca.PathNode = st.it
    guard @tutuca.step_get(prev_node, step) is Some(next_node) else { // bad path item (JS warns and returns null)
      return None
    }
    let next = next_node.as_value().unwrap_or(@tutuca.Value::Null)
    st = step_enter_frame(step, st, next)
  }
  Some(st)
}
