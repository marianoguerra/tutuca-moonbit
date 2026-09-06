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
  inline? : Bool = false,
) -> Unit raise NoSpelling {
  match node {
    // Whitespace the HTML tokenizer made out of the file's LAYOUT is not
    // content and is not printed: the new notation writes the whitespace it
    // means, so carrying the old file's indentation across would be carrying a
    // tokenizer artifact into a file that has no tokenizer.
    // A text node that survived the parser's condensing pass is CONTENT, even
    // when it holds nothing but a space: the space between `<span>` and
    // `<small>` is what separates two words on the page. The pass has already
    // taken out the ones that were the old file's layout, so anything left is
    // the author's.
    Text(d) => {
      // `collapse` answers "" for a run that is all whitespace, because it
      // writes a space only before a character it kept. A node that IS the
      // separator has one character, and it is that space.
      let collapsed = collapse(d.val)
      let text = if collapsed == "" { " " } else { collapsed }
      // A space at either END of a text node is content — it is what
      // separates `You must` from the `<span>STOP</span>` beside it — and a
      // text run written across lines cannot hold one: the newline and the
      // indentation around it are layout, and the reader cuts them. The
      // quoted form says the characters outright, so nothing trims them.
      if text.has_prefix(" ") || text.has_suffix(" ") {
        out.write_string("\{indent}@\{quote(text)}\n")
      } else {
        out.write_string("\{indent}\{escape_text(text)}\n")
      }
    }
    // A comment is a NODE — it reaches the DOM — and at-notation has no
    // spelling for one: `//` in shrubbery is a comment in the FILE, which is
    // not the same thing and would silently drop it.
    //
    // The one exception is the comment `ANode::parse` synthesises for a view
    // with no content. That is a parser artifact rather than something the
    // author wrote, and it is what an empty `<template>` comes back as.
    // A comment NODE reaches the DOM and has a form of its own; `//` in
    // shrubbery is a comment in the FILE and would drop it. The one exception
    // is the comment `ANode::parse` synthesises for a view with no content,
    // which is a parser artifact rather than something the author wrote.
    Comment(d) =>
      if d.val.trim(chars=" \n\t\r") != "" && !is_parse_artifact(d.val) {
        out.write_string("\{indent}@comment{\{escape_text(collapse(d.val))}}\n")
      }
    RenderText(d) => out.write_string("\{indent}@(\{print_expr(d.val)})\n")
    Dom(d) => print_element(d, events, indent, out, inline~)
    Fragment(d) =>
      for c in d.childs {
        print_node(c, events, indent, out)
      }
    Show(d) =>
      print_wrapper("show", d.val, d.node, events, indent, out, inline~)
    Hide(d) =>
      print_wrapper("hide", d.val, d.node, events, indent, out, inline~)
    Each(d) => print_each(d, events, indent, out, inline~)
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
    // A `Slot` in a parsed tree is a CALL SITE's content for one named slot —
    // `<x slot="actions">…</x>`. The placeholder inside a macro body is a
    // different node that the parser grafts away, and `print_macro` refuses a
    // body that has one rather than printing it as this.
    Slot(d) => {
      out.write_string("\{indent}@fill(\{quote(d.name)}){\n")
      print_node(d.node, events, indent + "  ", out)
      out.write_string("\{indent}}\n")
    }
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
  inline? : Bool = false,
) -> Unit raise NoSpelling {
  if inline {
    out.write_string("@\{word}(\{print_expr(cond)}){")
    print_node(inner, events, "", out, inline=true)
    out.write_string("}")
    return
  }
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
  inline? : Bool = false,
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
  if inline {
    out.write_string("@each(\{opts}){")
    print_node(d.node, events, "", out, inline=true)
    out.write_string("}")
    return
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
    "@\{macro_name(d.name)}()"
  } else {
    "@\{macro_name(d.name)}(\{args.join(", ")})"
  }
  // Only a call that actually passes content gets a body. A macro with no slot
  // content carries one empty `Fragment` under the default slot name, and
  // writing `{}` for it would put an empty block in the file.
  let body = StringBuilder()
  for _, slot in d.slots {
    print_node(slot, events, indent + "  ", body)
  }
  if body.to_string() == "" {
    out.write_string("\{indent}\{head}\n")
    return
  }
  out.write_string("\{indent}\{head}{\n")
  out.write_string(body.to_string())
  out.write_string("\{indent}}\n")
}

///|
/// One macro argument, which arrives as text in the old value notation.
fn macro_arg(source : String) -> String raise NoSpelling {
  // A macro argument reaches here as SOURCE TEXT in the old notation
  // (`Attrs::to_macro_vars`), because that is the only shape the old path had
  // for one. So it is read with the parser that wrote it and printed like any
  // other expression — reprinting the text would put the old spelling in a new
  // file, and a macro argument is an expression in the new notation.
  let e = @tscript.parse_macro_attr(source, @tscript.ParseCtx::new())
  guard e is Some(e) else {
    raise NoSpelling(
      what="a macro argument that does not parse (`\{source}`)",
      help="fix it in the `.html` file before converting",
    )
  }
  print_expr(e)
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

///|
/// A macro's name, as the new notation spells it.
///
/// The old notation put a macro in a TAG (`<x:btn-rm>`), where a hyphen is
/// ordinary; here it is a call, where a hyphen is the subtraction operator.
/// `snake_of` alone leaves it, so `@btn-rm(…)` read as `btn` minus `rm(…)`.
pub fn macro_name(name : String) -> String {
  @names.snake_of(name).replace_all(old="-", new="_")
}
