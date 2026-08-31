// ANode → Vdom traversal (the tree-building third of the renderer; the
// component and event thirds are mocked/deferred per render-plan.md).

///|
fn render_childs(
  nodes : Array[@anode.ANode],
  stack : RenderStack,
  ctx : RenderCtx,
) -> Array[@vdom.Vdom] {
  let rendered : Array[@vdom.Vdom] = []
  for node in nodes {
    if render(node, stack, ctx) is Some(child) {
      rendered.push(child)
    }
  }
  rendered
}

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
      // Upstream keeps null child slots in the array; our Vdom drops suppressed
      // children instead (no null nodes).
      let ns : @vdom.Ns? = match d.ns {
        Some(Svg) => Some(Svg)
        Some(MathML) => Some(MathMl)
        None => None
      }
      let built = @vdom.h(
        d.tag,
        attrs=eval_attrs(d.attrs, stack),
        childs=render_childs(d.childs, stack, ctx),
        ns?,
      )
      // Sanitize the element HERE, where it is built, rather than by walking
      // the finished tree. This is the only place `render` constructs one, so
      // every element is filtered exactly once — and a subtree the render cache
      // hands back was never rebuilt, so it is not filtered again. Over the
      // finished tree the filter re-walked every cached subtree on every
      // render: O(whole tree) beside a pipeline that is otherwise O(changed).
      //
      // Children are already built (the argument above), so a filter that
      // replaces them — raw markup becoming described nodes — is replacing
      // finished nodes, and is responsible for what it builds. `MarkupFilter`
      // sanitizes its own output for exactly this reason.
      //
      // The hints say which of the filter's rules can concern this element at
      // all. That is a fact about attribute NAMES, which are literals in a
      // view, so it is decided once per element instead of by scanning the
      // attribute map on every render. See `sink_hints.mbt`.
      if ctx.filter is Some(f) && built is Node(el) {
        f.filter_elem_hinted(el, sink_hints(d))
      }
      Some(built)
    }
    Fragment(d) => Some(@vdom.fragment(render_childs(d.childs, stack, ctx)))
    // The raw evaluated value goes into the child list;
    // a null drops out, everything else stringifies.
    RenderText(d) =>
      match d.val.eval(stack) {
        Null => None
        v => Some(@vdom.text(v.to_display_string()))
      }
    Render(d) => {
      let (value, render_path, base) = render_target(d.val, stack)
      render_site(
        value,
        d.view_val,
        Some(d.node_id),
        stack,
        ctx,
        render_path~,
        base?,
      )
    }
    RenderIt(d) =>
      render_site(
        stack.it,
        d.view_val,
        Some(d.node_id),
        stack,
        ctx,
        render_path=stack.render_path,
        base?=if stack.pending_frame {
          Some(stack.render_path.to_transaction_path())
        } else {
          None
        },
      )
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
  }
}

///|
/// Resolve a render operand together with the dispatch continuation it enters.
/// A dynamic/lexical name supplies an absolute app path and therefore pushes a
/// frame; an ordinary field extends the current frame.
fn render_target(
  val : @tutuca.Val,
  stack : RenderStack,
) -> (@tutuca.Value, @tutuca.DispatchPath, @tutuca.Path?) {
  match val {
    // A `*name` that resolved to a pathless value (a constant default, or a
    // position that could not be written down) reads fine but has nowhere to
    // resume, so it enters no frame.
    Dyn(name) =>
      match stack.lookup_dynamic_located(name) {
        Some({ value, path: Some(path), }) =>
          (value, stack.render_path.push_frame(path), Some(path))
        Some({ value, path: None, }) => (value, stack.render_path, None)
        None => (val.eval(stack), stack.render_path, None)
      }
    _ =>
      match val.to_path_item() {
        Some(step) => {
          let path = stack.render_path.concat([step])
          (
            val.eval(stack),
            path,
            if stack.pending_frame {
              Some(path.to_transaction_path())
            } else {
              None
            },
          )
        }
        None => (val.eval(stack), stack.render_path, None)
      }
  }
}

///|
/// Stamp every element root of a component body. A fragment has one comment
/// boundary before its first child, so later root siblings need the same base
/// on the element to reconstruct an event without seeing that comment.
/// Takes the ENCODED base, so a path with no wire form stamps nothing here and
/// writes no `base` into the §Comp§ meta either — the two cannot disagree.
fn stamp_render_base(vdom : @vdom.Vdom, text : String) -> @vdom.Vdom {
  match vdom {
    Node(el) => {
      let attrs = el.attrs.copy()
      attrs["data-rp"] = Str(text)
      Node({ ..el, attrs, })
    }
    Fragment(childs) =>
      Fragment(childs.map(child => stamp_render_base(child, text)))
    Text(_) | Comment(_) => vdom
  }
}

///|
/// `<x render>` / `<x render-it>`: enter a frame on the rendered value and
/// render the resolved view behind a §Comp§ boundary meta.
/// An unresolved view suppresses the site; a component whose view renders
/// nothing emits NO meta — a dangling boundary would make event-path
/// reconstruction cross an absent component.
fn render_site(
  value : @tutuca.Value,
  view_val : @tutuca.Val?,
  node_id : Int?,
  stack : RenderStack,
  ctx : RenderCtx,
  view? : String = "",
  render_path? : @tutuca.DispatchPath,
  base? : @tutuca.Path,
) -> @vdom.Vdom? {
  // Before anything is resolved or cached: a site that would re-enter the
  // value already being rendered leaves a marker instead of recursing. It
  // emits no §Comp§ boundary, for the same reason a view that renders nothing
  // does not — event-path reconstruction must not cross an absent component.
  if stack.would_recurse(value) {
    return Some(@vdom.comment("RECURSION AVOIDED"))
  }
  let site_path = render_path.unwrap_or(stack.render_path)
  // The `as=` selector evaluates against the HOST stack;
  // without one, the `@push-view` trail applies innermost-first.
  //
  // `view~` is neither: a name the MOUNTER chose, which no expression in the
  // tree can have said. It is only ever passed at the root, and it wins there
  // because there is nothing above it to have pushed a trail.
  let names : Array[String] = if view != "" {
    [view]
  } else {
    match view_val {
      Some(v) => [v.eval(stack).to_display_string()]
      None => stack.view_trail()
    }
  }
  match ctx.view_resolver.resolve_view(names, value) {
    Some(rv) => {
      // Decline before spending anything on a value with no bucket: a plain
      // A Map/List render site under a component-less resolver has
      // nothing whose generations can be told apart, so keying on it could
      // only build a key and miss. (OPTIMIZATIONS #8: the previous cache lost
      // time on exactly that.)
      let slot = match (ctx.render_cache, value.identity()) {
        (Some(cache), Some(id)) =>
          match
            cache.get(
              id,
              node_id,
              rv,
              value,
              stack.dyn_binds,
              stack.view_names,
              site_path,
              base,
            ) {
            Some(v) => return Some(v)
            None => Some((cache, id))
          }
        _ => None
      }
      match
        render(
          rv.node,
          stack.enter(
            value,
            Map([]),
            render_path=site_path,
            pending_frame=false,
          ),
          ctx,
        ) {
        Some(raw_body) => {
          let body = match base.bind(render_path_text) {
            Some(text) => stamp_render_base(raw_body, text)
            None => raw_body
          }
          let frag = @vdom.fragment([
            Meta::Comp(nid=node_id, cid=rv.cid, vid=rv.vid, base~).to_comment(),
            body,
          ])
          // Cache only a rendered (non-null) body.
          if slot is Some((cache, id)) {
            cache.set(
              id,
              node_id,
              rv,
              value,
              stack.dyn_binds,
              stack.view_names,
              site_path,
              base,
              frag,
            )
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
/// Render the tree from its root.
///
/// `view~` names which of the root component's views to render it under, and
/// "" — the default — is the ordinary resolution every render site uses. It is
/// the one thing a VALUE cannot say about itself: a `Todo` has a `main` and a
/// `row`, both over the same fields, and which one it should be shown as is a
/// fact about the showing rather than about the todo. A name the component does
/// not declare falls back to `main`, exactly as every other view name does
/// (`best_name`).
pub fn render_root(
  value : @tutuca.Value,
  stack : RenderStack,
  ctx : RenderCtx,
  view? : String = "",
) -> @vdom.Vdom? {
  render_site(value, None, None, stack, ctx, view~)
}

///|
/// A loop key value -> PathKey, for the item lookup and the §Each§ meta.
///
/// `as_key` refuses a non-integral number, where this must still produce a
/// key: the meta is a breadcrumb, and one that says KInt(-1) is how a key the
/// renderer could not name has always been recorded.
fn value_seq_key(v : @tutuca.Value) -> @tutuca.PathKey {
  v.as_key().unwrap_or(KInt(-1))
}

///|
fn keyed_path(path : @tutuca.Path, key : @tutuca.PathKey) -> @tutuca.Path? {
  guard path.steps is [.. init, last] else { return None }
  match last {
    FieldStep(field) =>
      Some(@tutuca.Path::new(steps=[..init, SeqStep(field~, key~)]))
    SeqStep(field~, ..) | EachRenderItStep(field~, ..) =>
      Some(@tutuca.Path::new(steps=[..init, SeqStep(field~, key~)]))
    _ => None
  }
}

///|
/// `@each` / `<x render-each>`: run @loop-with for the
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
  // A dynamic sequence carries the absolute path it lives at, so each item is
  // that path keyed — iterating it resumes there exactly as rendering one does.
  let located_seq : @tutuca.Path? = match d.iter_info.val {
    Dyn(name) =>
      match stack.lookup_dynamic_located(name) {
        Some({ path: Some(p), .. }) => Some(p)
        _ => None
      }
    _ => None
  }
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
  // `of_value` always fills the default, so this is the handler's iterData or
  // the `{ seq }` stand-in — never absent.
  let iter_data = plan.iter_data.unwrap_or(Null)
  let out : Array[@vdom.Vdom] = []
  fn visit(key : @tutuca.Value, value : @tutuca.Value, apply_filter : Bool) {
    // filter.call(it, key, value, iterData); default always-true. A keys
    // list from @loop-with is authoritative and skips it.
    if apply_filter &&
      filter_h is Some(f) &&
      !call_handler(f, it, [key, value, iter_data]).is_truthy() {
      return
    }
    let binds : Map[String, @tutuca.Value] = { "key": key, "value": value }
    if enrich_h is Some(e) {
      // callEnricher(enricher, it, binds, key, value, iterData); the
      // loop's own binds are restored unconditionally afterwards.
      call_handler(e, it, [Map(binds), key, value, iter_data]) |> ignore
      binds["key"] = key
      binds["value"] = value
    }
    let pk = value_seq_key(key)
    let (item_path, pending) = match located_seq {
      Some(seq_path) =>
        match keyed_path(seq_path, pk) {
          Some(base) => (stack.render_path.push_frame(base), true)
          None => (stack.render_path, false)
        }
      // `@each` re-binds `it` to the item whether or not the body is a
      // component, so the render position moves either way and the step has to
      // ADDRESS it: `.rows` iterated at `key` is `rows[key]`. Keying off the
      // body node instead left a plain `<div @each><x render-it>` — the
      // canonical spelling — contributing a frame-only step, so everything the
      // item published claimed the address of the whole collection's owner.
      //
      // A sequence that is not a plain field cannot be written down (a
      // seq-access iterated at a key is not an expressible Path), so the
      // position stays put and `publish_base` refuses to publish it.
      None =>
        match d.iter_info.val {
          Field(field) =>
            (stack.render_path.concat([SeqStep(field~, key=pk)]), false)
          _ => (stack.render_path, false)
        }
    }
    match
      render(
        d.node,
        stack.enter(
          value,
          binds,
          is_frame=false,
          render_path=item_path,
          pending_frame=pending,
        ),
        ctx,
      ) {
      Some(v) => {
        // One §Each§ meta precedes each visible item; a
        // hidden item leaves neither entry nor dangling meta.
        out.push(Meta::Each(nid=d.node_id, key=pk).to_comment())
        out.push(v)
      }
      None => ()
    }
  }

  match plan.keys {
    Some(ks) =>
      // An explicit key list addresses List, Map and a custom-collection Obj
      // through the one lookup (@tutuca).
      for k in ks {
        visit(k, seq.item(value_seq_key(k)), false)
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
        // custom seq: iterate the Obj's ordered entries,
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
                visit(pk.to_value(), v, true)
              }
            }
            None => () // not a sequence -> empty
          }
        // Anything else iterates as empty.
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
            // Unset branch evaluates to null → omit.
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
            // { __html: `${val.eval(stack)}` } under the fixed name.
            let html = match val {
              Some(v) => v.eval(stack).to_display_string()
              None => "null" // the null sentinel interpolates to "null"
            }
            out["dangerouslySetInnerHTML"] = Html(html)
          }
          RawMarkdown(val~) => {
            let md = match val {
              Some(v) => v.eval(stack).to_display_string()
              None => "null" // same sentinel as RawHtml above
            }
            out["setInnerMd"] = Md(md)
          }
          SafeHtml(val~) => {
            let html = match val {
              Some(v) => v.eval(stack).to_display_string()
              None => "null" // same sentinel as RawHtml above
            }
            out["setInnerHtml"] = SafeHtml(html)
          }
          SafeSvg(val~) => {
            let svg = match val {
              Some(v) => v.eval(stack).to_display_string()
              None => "null" // same sentinel as RawHtml above
            }
            out["setInnerSvg"] = Svg(svg)
          }
        }
      }
  }
  out
}
