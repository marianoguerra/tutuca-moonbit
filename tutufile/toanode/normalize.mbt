// Comparing a tree this package built with a tree the HTML parser built.
//
// The two disagree about whitespace and always will: one takes the text the
// file wrote, the other takes what a tokenizer made of the file's LAYOUT and
// then repairs it with a block/inline table. Neither is wrong about anything
// except the other, so a comparison that means something has to look past it.
//
// This is that comparison, and it is a normalizer rather than a bespoke `Eq`
// so that the thing it ignores is written down and reviewable. It is used by
// the equivalence tests and by `tutufile/equiv`, which is the acceptance check
// for converting a view file — the same question in both places.

///|
/// A copy of the tree with whitespace-only text dropped and the rest collapsed
/// to single spaces.
///
/// A COPY, not a mutation: the tree is shared and the caller usually wants to
/// keep the original to render.
pub fn strip_ws(node : @anode.ANode) -> @anode.ANode {
  match node {
    Text(d) => @anode.text(collapse_ws(d.val))
    Comment(d) => @anode.comment(collapse_ws(d.val))
    Dom(d) =>
      Dom({
        tag: d.tag,
        attrs: d.attrs,
        childs: strip_kids(d.childs),
        ns: d.ns,
        // A memo `render` fills, and never a fact about the source. Dropping it
        // keeps two trees from differing over which of them has been rendered.
        sink_hints: None,
        bind: d.bind,
      })
    Fragment(d) => Fragment({ childs: strip_kids(d.childs), })
    Show(d) => Show({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Hide(d) => Hide({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    PushView(d) =>
      PushView({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Scope(d) =>
      Scope({ node_id: d.node_id, val: d.val, node: strip_ws(d.node), })
    Slot(d) => Slot({ name: d.name, node: strip_ws(d.node), })
    Each(d) =>
      Each({
        node_id: d.node_id,
        iter_info: d.iter_info,
        node: strip_ws(d.node),
        from_render_each: d.from_render_each,
      })
    other => other
  }
}

///|
fn strip_kids(cs : Array[@anode.ANode]) -> Array[@anode.ANode] {
  let out = []
  for c in cs {
    let k = strip_ws(c)
    if k is (Text(d) | Comment(d)) && d.val == "" {
      continue
    }
    out.push(k)
  }
  out
}

///|
/// Runs of whitespace to one space, ends trimmed.
pub fn collapse_ws(s : String) -> String {
  let words = []
  let cur = StringBuilder()
  for c in s {
    if c is (' ' | '\t' | '\n' | '\r') {
      if cur.to_string() != "" {
        words.push(cur.to_string())
        cur.reset()
      }
    } else {
      cur.write_char(c)
    }
  }
  if cur.to_string() != "" {
    words.push(cur.to_string())
  }
  words.join(" ")
}

///|
/// A copy of the tree with every operator chain reduced to the applications it
/// evaluates as.
///
/// The two paths spell an operator differently and mean the same thing. A SLOT
/// parser reads `(.a is 'x')` as `EApp("is", [a, b])` — the prefix form the old
/// attribute text was written in — while the block grammar reads `a == b` as an
/// `EChain` carrying its family. `eval_chain` (`core/value_eval.mbt`) reduces a
/// chain to exactly this nest of `EApp` before evaluating it, and `Position`
/// gives `EApp`, `EChain` and `EUnary` one kind, so no position tells them
/// apart either.
///
/// Going direct produces the CHAIN, because a body and a slot are one language.
/// This is what lets a tree built that way be compared with one an old-notation
/// parser built.
pub fn flatten_ops(node : @anode.ANode) -> @anode.ANode {
  map_exprs(node, flat_expr)
}

///|
/// One expression, with its chains reduced.
pub fn flat_expr(e : @tutuca.Expr) -> @tutuca.Expr {
  match e {
    EChain(ops~, operands~, span~, ..) => {
      let mut acc = flat_expr(operands[0])
      for i, op in ops {
        acc = EApp(name=op, args=[acc, flat_expr(operands[i + 1])], span~)
      }
      acc
    }
    EUnary(op=UNot, operand~, span~) =>
      EApp(name="not", args=[flat_expr(operand)], span~)
    EApp(name~, args~, span~) => EApp(name~, args=args.map(flat_expr), span~)
    ETpl(parts~, span~) =>
      ETpl(
        parts=parts.map(p => {
          match p {
            TExpr(v) => TExpr(flat_expr(v))
            other => other
          }
        }),
        span~,
      )
    EIf(cond~, then_~, else_~, span~) =>
      EIf(
        cond=flat_expr(cond),
        then_=flat_expr(then_),
        else_=flat_expr(else_),
        span~,
      )
    ERead(place~, span~) => ERead(place=flat_place(place), span~)
    ERef(place~, span~) => ERef(place=flat_place(place), span~)
    other => other
  }
}

///|
fn flat_place(place : @tutuca.Place) -> @tutuca.Place {
  {
    root: place.root,
    steps: place.steps.map(s => {
      match s {
        PIndex(k) => PIndex(flat_expr(k))
        other => other
      }
    }),
    span: place.span,
  }
}

///|
/// A copy of the tree with `f` applied to every expression in it.
///
/// One walk rather than one per normalizer: the list of places an expression
/// hides in a node is a fact about `ANode` and is worth stating once.
fn map_exprs(
  node : @anode.ANode,
  f : (@tutuca.Expr) -> @tutuca.Expr,
) -> @anode.ANode {
  fn kids(cs : Array[@anode.ANode]) -> Array[@anode.ANode] {
    cs.map(c => map_exprs(c, f))
  }

  match node {
    Dom(d) =>
      Dom({
        tag: d.tag,
        attrs: map_attrs(d.attrs, f),
        childs: kids(d.childs),
        ns: d.ns,
        sink_hints: None,
        bind: match d.bind {
          Some(b) =>
            Some({ target: f(b.target), property: b.property, event: b.event, })
          None => None
        },
      })
    Fragment(d) => Fragment({ childs: kids(d.childs), })
    RenderText(d) => RenderText({ node_id: d.node_id, val: f(d.val), })
    Render(d) =>
      Render({ node_id: d.node_id, val: f(d.val), view_val: d.view_val.map(f), })
    RenderIt(d) =>
      RenderIt({ node_id: d.node_id, view_val: d.view_val.map(f), })
    Show(d) =>
      Show({ node_id: d.node_id, val: f(d.val), node: map_exprs(d.node, f), })
    Hide(d) =>
      Hide({ node_id: d.node_id, val: f(d.val), node: map_exprs(d.node, f), })
    PushView(d) =>
      PushView({
        node_id: d.node_id,
        val: f(d.val),
        node: map_exprs(d.node, f),
      })
    Scope(d) =>
      Scope({ node_id: d.node_id, val: f(d.val), node: map_exprs(d.node, f), })
    Slot(d) => Slot({ name: d.name, node: map_exprs(d.node, f), })
    Each(d) =>
      Each({
        node_id: d.node_id,
        iter_info: {
          val: f(d.iter_info.val),
          when_val: d.iter_info.when_val.map(f),
          loop_with_val: d.iter_info.loop_with_val.map(f),
          enrich_with_val: d.iter_info.enrich_with_val.map(f),
        },
        node: map_exprs(d.node, f),
        from_render_each: d.from_render_each,
      })
    other => other
  }
}

///|
fn map_attrs(
  attrs : @anode.Attrs,
  f : (@tutuca.Expr) -> @tutuca.Expr,
) -> @anode.Attrs {
  match attrs {
    ConstAttrs(_) => attrs
    DynAttrs(items) =>
      DynAttrs(
        items.map(item => {
          match item {
            ConstA(name~, val~) => ConstA(name~, val=f(val))
            Plain(name~, val~) => Plain(name~, val=f(val))
            RawHtml(val~) => RawHtml(val=val.map(f))
            RawMarkdown(val~) => RawMarkdown(val=val.map(f))
            SafeHtml(val~) => SafeHtml(val=val.map(f))
            SafeSvg(val~) => SafeSvg(val=val.map(f))
            If(a) =>
              If({
                name: a.name,
                cond_val: f(a.cond_val),
                then_val: a.then_val.map(f),
                else_val: a.else_val.map(f),
              })
          }
        }),
      )
  }
}

///|
/// A copy of the tree with every macro call replaced by its expansion.
///
/// The old path keeps a `MacroCall` node holding the expansion inside it; the
/// direct reader substitutes the macro's body in place and adds no node. The
/// ahead-of-time generator already strips the wrapper (`viewgen`'s
/// `strip_macro_calls`), so expanding in place is the end state it was reaching
/// for — and a comparison between the two paths has to look past a node that
/// only one of them builds.
///
/// A call that was never expanded is left alone: it is a macro the scope did
/// not have, which is a difference worth seeing.
pub fn strip_macro_calls(node : @anode.ANode) -> @anode.ANode {
  match node {
    MacroCall(d) =>
      match d.node {
        Some(inner) => strip_macro_calls(inner)
        None => node
      }
    Dom(d) =>
      Dom({
        tag: d.tag,
        attrs: d.attrs,
        childs: d.childs.map(strip_macro_calls),
        ns: d.ns,
        sink_hints: None,
        bind: d.bind,
      })
    Fragment(d) => Fragment({ childs: d.childs.map(strip_macro_calls), })
    Show(d) =>
      Show({ node_id: d.node_id, val: d.val, node: strip_macro_calls(d.node), })
    Hide(d) =>
      Hide({ node_id: d.node_id, val: d.val, node: strip_macro_calls(d.node), })
    PushView(d) =>
      PushView({
        node_id: d.node_id,
        val: d.val,
        node: strip_macro_calls(d.node),
      })
    Scope(d) =>
      Scope({ node_id: d.node_id, val: d.val, node: strip_macro_calls(d.node), })
    Slot(d) => Slot({ name: d.name, node: strip_macro_calls(d.node), })
    Each(d) =>
      Each({
        node_id: d.node_id,
        iter_info: d.iter_info,
        node: strip_macro_calls(d.node),
        from_render_each: d.from_render_each,
      })
    other => other
  }
}
