// ANode → Vdom traversal (the tree-building third of src/renderer.js; the
// component and event thirds are mocked/deferred per render-plan.md).

///|
pub fn render(
  node : @anode.ANode,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom? {
  match node {
    Text(d) => Some(@vdom.text(d.val))
    Comment(d) => Some(@vdom.comment(d.val))
    Dom(d) => {
      // JS keeps null child slots in the array; our Vdom drops suppressed
      // children instead (no null nodes).
      let childs : Array[@vdom.Vdom] = []
      for c in d.childs {
        match render(c, stack, ctx) {
          Some(v) => childs.push(v)
          None => ()
        }
      }
      let ns : @vdom.Ns? = match d.ns {
        Some(Svg) => Some(Svg)
        Some(MathML) => Some(MathMl)
        None => None
      }
      Some(@vdom.h(d.tag, attrs=eval_attrs(d.attrs, stack), childs~, ns?))
    }
    Fragment(d) => {
      let childs : Array[@vdom.Vdom] = []
      for c in d.childs {
        match render(c, stack, ctx) {
          Some(v) => childs.push(v)
          None => ()
        }
      }
      Some(@vdom.fragment(childs))
    }
    // JS RenderTextNode returns the raw evaluated value into the child list;
    // a null drops out, everything else stringifies.
    RenderText(d) =>
      match d.val.eval(stack) {
        Null => None
        v => Some(@vdom.text(v.to_display_string()))
      }
    Render(d) =>
      render_site(d.val.eval(stack), d.view_val, Some(d.node_id), stack, ctx)
    RenderIt(d) =>
      render_site(stack.it, d.view_val, Some(d.node_id), stack, ctx)
    Show(d) =>
      if d.val.eval(stack).is_truthy() {
        render(d.node, stack, ctx)
      } else {
        None
      }
    Hide(d) =>
      if d.val.eval(stack).is_truthy() {
        None
      } else {
        render(d.node, stack, ctx)
      }
    PushView(d) =>
      render(
        d.node,
        stack.push_view_name(d.val.eval(stack).to_display_string()),
        ctx,
      )
    // Slots were substituted during parse/macro expansion.
    Slot(d) => render(d.node, stack, ctx)
    Scope(d) => {
      // JS: binds = val.evalAsHandler(stack)?.call(stack.it) ?? {}.
      let handler = d.val.eval_as_handler(stack)
      let binds : Map[String, @tutuca.Value] = match
        call_handler(handler, stack.it, []) {
        Map(m) => m
        _ => Map([])
      }
      // Prefix the subtree with a §Scope§ meta so event-path reconstruction
      // can replay this scope's binds (mirrors §Each§/§Comp§). A suppressed
      // subtree leaves no dangling meta.
      match render(d.node, stack.enter(stack.it, binds, is_frame=false), ctx) {
        Some(dom) =>
          match d.node_id {
            Some(nid) =>
              Some(@vdom.fragment([Meta::Scope(nid~).to_comment(), dom]))
            None => Some(dom)
          }
        None => None
      }
    }
    Each(d) => render_each(d, stack, ctx)
    MacroCall(d) =>
      match d.node {
        Some(n) => render(n, stack, ctx)
        None => Some(@vdom.comment("bad macro: \{d.name}"))
      }
    // Constant subtree: render once, then reuse the same Vdom on every later
    // hit (JS RenderOnceNode memoizes on the node instance; the port keys on
    // the marker id). Returning the identical Vdom lets morph short-circuit
    // the subtree via Vdom::is_equal_to's physical_equal fast path.
    RenderOnce(m) =>
      match ctx.render_once.get(m.id) {
        Some(v) => Some(v)
        None =>
          match render(m.node, stack, ctx) {
            Some(v) => {
              ctx.render_once[m.id] = v
              Some(v)
            }
            None => None
          }
      }
  }
}

///|
pub fn render_view(
  view : @anode.View,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom {
  match view.anode {
    Some(node) =>
      render(node, stack, ctx).unwrap_or(
        @vdom.comment("view \{view.name} rendered nothing"),
      )
    None => @vdom.comment("view \{view.name} was not compiled")
  }
}

///|
/// `<x render>` / `<x render-it>`: enter a frame on the rendered value and
/// render the resolved view behind a §Comp§ boundary meta (JS _rValComp).
/// An unresolved view suppresses the site; a component whose view renders
/// nothing emits NO meta — a dangling boundary would make event-path
/// reconstruction cross an absent component (JS null-body fix).
fn render_site(
  value : @tutuca.Value,
  view_val : @tutuca.Val?,
  node_id : Int?,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom? {
  // The `as=` selector evaluates against the HOST stack (JS evalViewName);
  // without one, the `@push-view` trail applies innermost-first.
  let names : Array[String] = match view_val {
    Some(v) => [v.eval(stack).to_display_string()]
    None => stack.view_trail()
  }
  match ctx.view_resolver.resolve_view(names, value) {
    Some(rv) => {
      // Cache lookup (JS _rValComp): a hit returns the reused fragment when the
      // site's value + dynamic-binding context are physically unchanged.
      let slot = match ctx.render_cache {
        Some(cache) => {
          let key = site_cache_key(rv, node_id, stack)
          match cache.get(key, value, stack.dyn_binds) {
            Some(v) => return Some(v)
            None => Some(key)
          }
        }
        None => None
      }
      match render(rv.node, stack.enter(value, Map([])), ctx) {
        Some(body) => {
          let frag = @vdom.fragment([
            Meta::Comp(nid=node_id, cid=rv.cid, vid=rv.vid).to_comment(),
            body,
          ])
          // JS caches only a rendered (non-null) body.
          match (ctx.render_cache, slot) {
            (Some(cache), Some(key)) =>
              cache.set(key, value, stack.dyn_binds, frag)
            _ => ()
          }
          Some(frag)
        }
        None => None
      }
    }
    None => None
  }
}

///|
/// The per-slot cache string (JS _rValComp cacheKey): resolved view identity +
/// the inherited @push-view trail + the render-site node id + the innermost
/// loop key (so sibling list items of the same component cache separately).
/// `\x1f` can't appear in a view name or key, so the fields can't merge.
fn site_cache_key(
  rv : ResolvedView,
  node_id : Int?,
  stack : RenderStack,
) -> String {
  let nid = match node_id {
    Some(n) => n.to_string()
    None => ""
  }
  let loop_key = match stack.binds.get("key") {
    Some(k) => k.to_display_string()
    None => ""
  }
  "\{rv.cid}\u{1f}\{rv.vid}\u{1f}\{stack.view_trail().join(",")}\u{1f}\{nid}\u{1f}\{loop_key}"
}

///|
pub fn render_root(
  value : @tutuca.Value,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom? {
  render_site(value, None, None, stack, ctx)
}

///|
/// PathKey -> the loop `@key` value (KInt -> Num, KStr -> Str).
fn seq_key_value(pk : @tutuca.PathKey) -> @tutuca.Value {
  match pk {
    KInt(i) => Num(i.to_double())
    KStr(s) => Str(s)
  }
}

///|
/// A loop key value -> PathKey for a custom-seq obj_item lookup.
fn value_seq_key(v : @tutuca.Value) -> @tutuca.PathKey {
  match v {
    Num(n) => KInt(n.to_int())
    Str(s) => KStr(s)
    _ => KInt(-1)
  }
}

///|
/// `@each` / `<x render-each>` (JS renderEachWhen): run @loop-with for the
/// plan (iterData / start / end / keys), iterate the sequence — an explicit
/// keys list is authoritative and skips @when; otherwise slice-ranged order
/// with @when filtering — seed {key, value} binds, run @enrich-with, and
/// render the wrapped node once per item with the ITEM as the new `it`,
/// each behind its §Each§ meta.
fn render_each(
  d : @anode.EachData,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom? {
  let seq = d.iter_info.val.eval(stack)
  let it = stack.it
  let filter_h : @tutuca.Value? = match d.iter_info.when_val {
    Some(v) => Some(v.eval_as_handler(stack))
    None => None
  }
  let enrich_h : @tutuca.Value? = match d.iter_info.enrich_with_val {
    Some(v) => Some(v.eval_as_handler(stack))
    None => None
  }
  let plan = loop_plan(stack, seq, filter_h, d.iter_info.loop_with_val)
  let iter_data = plan.iter_data
  let out : Array[@vdom.Vdom] = []
  fn visit(key : @tutuca.Value, value : @tutuca.Value, apply_filter : Bool) {
    // JS filter.call(it, key, value, iterData); default always-true. A keys
    // list from @loop-with is authoritative and skips it (JS imKeysIter).
    if apply_filter &&
      filter_h is Some(f) &&
      !call_handler(f, it, [key, value, iter_data]).is_truthy() {
      return
    }
    let binds : Map[String, @tutuca.Value] = { "key": key, "value": value }
    if enrich_h is Some(e) {
      // JS callEnricher(enricher, it, binds, key, value, iterData); the
      // loop's own binds are restored unconditionally afterwards (the JS
      // console.assert needs value equality, which the mock skips).
      call_handler(e, it, [Map(binds), key, value, iter_data]) |> ignore
      binds["key"] = key
      binds["value"] = value
    }
    match render(d.node, stack.enter(value, binds, is_frame=false), ctx) {
      Some(v) => {
        // One §Each§ meta precedes each visible item (JS pushEachEntry); a
        // hidden item leaves neither entry nor dangling meta.
        let pk : @tutuca.PathKey = match key {
          Num(n) => KInt(n.to_int())
          Str(s) => KStr(s)
          _ => KInt(-1)
        }
        out.push(Meta::Each(nid=d.node_id, key=pk).to_comment())
        out.push(v)
      }
      None => ()
    }
  }

  match plan.keys {
    Some(ks) =>
      for k in ks {
        match (seq, k) {
          (List(items), Num(n)) => {
            let i = n.to_int()
            visit(
              k,
              if i >= 0 && i < items.length() {
                items[i]
              } else {
                Null
              },
              false,
            )
          }
          (Map(m), Str(mk)) => visit(k, m.get(mk).unwrap_or(Null), false)
          // custom seq (JS SEQ_INFO): resolve the key through obj_item
          (Obj(o), _) =>
            visit(k, o.obj_item(value_seq_key(k)).unwrap_or(Null), false)
          _ => ()
        }
      }
    None =>
      match seq {
        List(items) => {
          let (s, e) = normalize_range(plan.start, plan.end, items.length())
          for i in s..<e {
            visit(Num(i.to_double()), items[i], true)
          }
        }
        Map(m) => {
          let names : Array[String] = []
          for k, _v in m {
            names.push(k)
          }
          let (s, e) = normalize_range(plan.start, plan.end, names.length())
          for i in s..<e {
            visit(Str(names[i]), m.get(names[i]).unwrap_or(Null), true)
          }
        }
        // custom seq (JS SEQ_INFO walker): iterate the Obj's ordered entries,
        // honoring the @loop-with [start, end) slice and preserving each key.
        Obj(o) =>
          match o.obj_seq_entries() {
            Some(entries) => {
              let (s, e) = normalize_range(
                plan.start,
                plan.end,
                entries.length(),
              )
              for i in s..<e {
                let (pk, v) = entries[i]
                visit(seq_key_value(pk), v, true)
              }
            }
            None => () // not a sequence -> empty (unkIter)
          }
        // Anything else iterates as empty (JS unkIter).
        _ => ()
      }
  }
  Some(@vdom.fragment(out))
}

///|
fn eval_attrs(
  attrs : @anode.Attrs,
  stack : RenderStack,
) -> Map[String, @vdom.AttrValue] {
  let out : Map[String, @vdom.AttrValue] = Map([])
  fn put(name : String, v : @vdom.AttrValue?) {
    if v is Some(av) {
      out[name] = av
    }
  }

  match attrs {
    ConstAttrs(m) =>
      for name, lit in m {
        put(name, lit_to_attr(lit))
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) =>
            put(name, value_to_attr(val.eval(stack)))
          If(ia) => {
            // Unset branch = JS NOT_SET_VAL, which evaluates to null → omit.
            let branch = if ia.cond_val.eval(stack).is_truthy() {
              ia.then_val
            } else {
              ia.else_val
            }
            match branch {
              Some(v) => put(ia.name, value_to_attr(v.eval(stack)))
              None => ()
            }
          }
          RawHtml(val~) => {
            // JS: { __html: `${val.eval(stack)}` } under the fixed name.
            let html = match val {
              Some(v) => v.eval(stack).to_display_string()
              None => "null" // JS NULL_CONST sentinel interpolates to "null"
            }
            out["dangerouslySetInnerHTML"] = Html(html)
          }
        }
      }
  }
  out
}
