// A compiled view tree, printed as the at-notation that produces it.

///|
/// One view's body, indented under its declaration.
pub fn print_view(
  node : @anode.ANode,
  events : Array[@anode.NodeEvents],
  indent : String,
) -> String raise NoSpelling {
  let out = StringBuilder()
  print_node(node, events, indent, out)
  out.to_string()
}

///|
/// One node and everything under it.
fn print_node(
  node : @anode.ANode,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  match node {
    // Whitespace the HTML tokenizer made out of the file's LAYOUT is not
    // content and is not printed: the new notation writes the whitespace it
    // means, so carrying the old file's indentation across would be carrying a
    // tokenizer artifact into a file that has no tokenizer.
    Text(d) =>
      if d.val.trim(chars=" \n\t\r") != "" {
        out.write_string("\{indent}\{escape_text(collapse(d.val))}\n")
      }
    // A comment is a NODE — it reaches the DOM — and at-notation has no
    // spelling for one: `//` in shrubbery is a comment in the FILE, which is
    // not the same thing and would silently drop it.
    //
    // The one exception is the comment `ANode::parse` synthesises for a view
    // with no content. That is a parser artifact rather than something the
    // author wrote, and it is what an empty `<template>` comes back as.
    Comment(d) =>
      if d.val.trim(chars=" \n\t\r") != "" && !is_parse_artifact(d.val) {
        raise NoSpelling(
          what="a comment node in a view (`\{collapse(d.val)}`)",
          help="at-notation has no spelling for a comment that reaches the DOM — delete it, or convert this view by hand",
        )
      }
    RenderText(d) => out.write_string("\{indent}@(\{print_expr(d.val)})\n")
    Dom(d) => print_element(d, events, indent, out)
    Fragment(d) =>
      for c in d.childs {
        print_node(c, events, indent, out)
      }
    Show(d) => print_wrapper("show", d.val, d.node, events, indent, out)
    Hide(d) => print_wrapper("hide", d.val, d.node, events, indent, out)
    Each(d) => print_each(d, events, indent, out)
    Render(d) => {
      let tail = match d.view_val {
        Some(v) => ", ~as: " + print_expr(v)
        None => ""
      }
      out.write_string("\{indent}@render(\{print_expr(d.val)}\{tail})\n")
    }
    RenderIt(d) => {
      let tail = match d.view_val {
        Some(v) => ", ~as: " + print_expr(v)
        None => ""
      }
      out.write_string("\{indent}@render(value\{tail})\n")
    }
    Slot(_) => out.write_string("\{indent}@slot\n")
    // Both are OPTIONS on the element they wrap rather than forms around it:
    // `~push_view:` pushes a view for the subtree, and a loop-less
    // `~enrich_with:` opens a scope frame. The wrapper node is what the parser
    // builds out of the attribute, so printing it back as one closes the loop.
    PushView(d) =>
      print_wrapped(
        d.node,
        "~push_view: " + print_expr(d.val),
        events,
        indent,
        out,
      )
    Scope(d) =>
      print_wrapped(
        d.node,
        "~enrich_with: " + print_trigger(d.val),
        events,
        indent,
        out,
      )
    MacroCall(d) => print_macro_call(d, events, indent, out)
  }
}

///|
/// Whether a comment is one the parser wrote rather than the author.
///
/// `ANode::parse` answers an empty view with one, and `Macro::expand` and
/// `macro_compile` write their own for a view or a macro that is not there.
/// None of them is content.
fn is_parse_artifact(text : String) -> Bool {
  let t = text.trim(chars=" \n\t\r").to_owned()
  t.has_prefix("Empty View") ||
  t.has_prefix("bad macro:") ||
  t.has_prefix("Error:")
}

///|
/// The element a wrapper wraps, with the wrapper's own option on it.
///
/// A wrapper node is what the parser BUILDS out of an attribute, so the way
/// back is the attribute — not a form around the element, which the notation
/// does not have and which would put a node in the tree the author did not
/// write.
fn print_wrapped(
  inner : @anode.ANode,
  option : String,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard inner is Dom(d) else {
    raise NoSpelling(
      what="a wrapper around something that is not an element",
      help="`~push_view:` and `~enrich_with:` are options ON an element, so the thing wrapped has to be one",
    )
  }
  print_element(d, events, indent, out, extra=[option])
}

///|
/// A `@show` / `@hide`, which wraps what it governs.
fn print_wrapper(
  word : String,
  cond : @tutuca.Expr,
  inner : @anode.ANode,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  out.write_string("\{indent}@\{word}(\{print_expr(cond)}){\n")
  print_node(inner, events, indent + "  ", out)
  out.write_string("\{indent}}\n")
}

///|
/// `@each(value, key in seq, …)`.
///
/// The binders are named `value` and `key` — the names the RENDERER answers a
/// loop with, and the names the tree already carries as `PBind`. Naming them
/// anything else would mean rewriting every read under the loop to match, for
/// no gain: the file's own binder names were not in the old notation to
/// recover.
fn print_each(
  d : @anode.EachData,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let opts = StringBuilder()
  opts.write_string("value, key in " + print_expr(d.iter_info.val))
  match d.iter_info.when_val {
    Some(v) => opts.write_string(", ~when: " + print_trigger(v))
    None => ()
  }
  match d.iter_info.enrich_with_val {
    Some(v) => opts.write_string(", ~enrich_with: " + print_trigger(v))
    None => ()
  }
  match d.iter_info.loop_with_val {
    Some(v) => opts.write_string(", ~loop_with: " + print_trigger(v))
    None => ()
  }
  out.write_string("\{indent}@each(\{opts}){\n")
  print_node(d.node, events, indent + "  ", out)
  out.write_string("\{indent}}\n")
}

///|
/// A render-time trigger names a handler; it is never evaluated.
fn print_trigger(e : @tutuca.Expr) -> String raise NoSpelling {
  match e {
    EName(name~, ..) | EMethod(name~, ..) => @names.snake_of(name)
    _ =>
      raise NoSpelling(
        what="a `@when` / `@enrich-with` that is not a name",
        help="a render-time trigger names a handler declared in `logic:`",
      )
  }
}

///|
/// A macro call: `@name(~arg: value)`.
fn print_macro_call(
  d : @anode.MacroData,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  // A macro call's arguments are SOURCE STRINGS on the old path
  // (`Attrs::to_macro_vars`), so they arrive here as text in the old value
  // notation. Printing them back out unread would put the old spelling in a new
  // file, so anything that is not a plain string literal is refused.
  let args = []
  for k, v in d.attrs {
    args.push("~\{@names.snake_of(k)}: \{macro_arg(v)}")
  }
  let head = if args.is_empty() {
    "@\{@names.snake_of(d.name)}()"
  } else {
    "@\{@names.snake_of(d.name)}(\{args.join(", ")})"
  }
  if d.slots.is_empty() {
    out.write_string("\{indent}\{head}\n")
    return
  }
  out.write_string("\{indent}\{head}{\n")
  for _, slot in d.slots {
    print_node(slot, events, indent + "  ", out)
  }
  out.write_string("\{indent}}\n")
}

///|
/// One macro argument, which arrives as text in the old value notation.
fn macro_arg(source : String) -> String raise NoSpelling {
  let t = source.trim(chars=" ").to_owned()
  if t.length() >= 2 && t.has_prefix("'") && t.has_suffix("'") {
    return quote(t[1:t.length() - 1].to_owned())
  }
  raise NoSpelling(
    what="a macro argument that is not a literal string (`\{source}`)",
    help="convert this call by hand: a macro argument reaches here as source text in the old notation, and reprinting it would put the old spelling in a new file",
  )
}

///|
/// Runs of whitespace to one space: what the tokenizer made of layout is not
/// content, and the parts of a text node that ARE content are separated by one
/// space however the old file wrapped them.
///
/// The EDGES are kept, as one space each. `<x text=".label"></x>: <span>` has
/// the text node `": "`, and the space after the colon is the space between two
/// words on the page — trimming it would change what is rendered.
fn collapse(s : String) -> String {
  let out = StringBuilder()
  let mut space = false
  let mut wrote = false
  for c in s {
    if c is (' ' | '\t' | '\n' | '\r') {
      space = true
    } else {
      if space && wrote {
        out.write_char(' ')
      } else if space {
        out.write_char(' ')
      }
      space = false
      wrote = true
      out.write_char(c)
    }
  }
  if space && wrote {
    out.write_char(' ')
  }
  out.to_string()
}
