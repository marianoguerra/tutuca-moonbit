// An element: its attributes, the handlers its `data-eid` points at, and its
// children.

///|
/// The `data-*` names the COMPILER stamps. They are not the author's and are
/// not printed — a converted file that carried them would be declaring, as
/// source, the identifiers the next compile is going to assign.
let stamped : Array[String] = ["data-vid", "data-cid", "data-nid"]

///|
fn print_element(
  d : @anode.DomData,
  events : Array[@anode.NodeEvents],
  indent : String,
  out : StringBuilder,
  extra? : Array[String] = [],
  inline? : Bool = false,
) -> Unit raise NoSpelling {
  let opts = []
  // A wrapper's own option, written first so it reads before the element's own.
  for e in extra {
    opts.push(e)
  }
  let extra : Array[(String, String)] = []
  let mut eid : Int? = None
  for item in attr_items(d.attrs) {
    match item {
      ConstA(name~, val~) => {
        if stamped.contains(name) {
          continue
        }
        // The handlers go where the `@on.*` attribute was, which is where the
        // parser put `data-eid`. Appending them instead would reorder the
        // element's attributes, and the tree compares attribute for attribute.
        if name == "data-eid" {
          eid = eid_of(val)
          if eid is Some(id) {
            for h in handlers_at(events, id) {
              opts.push(print_handler(h))
            }
          }
          continue
        }
        match option_name(name) {
          Some(opt) => opts.push("~\{opt}: \{print_expr(val)}")
          None => extra.push((name, print_expr(val)))
        }
      }
      Plain(name~, val~) => {
        // The property a `~bind:` mirrors is written by the bind, not beside
        // it: the parser inserted `value=` (or `checked=`) from `@bind` and
        // printing both would give the element the attribute twice.
        if d.bind is Some(b) && name == b.property {
          continue
        }
        match option_name(name) {
          Some(opt) => opts.push("~\{opt}: \{print_expr(val)}")
          None => extra.push((name, print_expr(val)))
        }
      }
      If(a) => {
        let then_ = match a.then_val {
          Some(v) => print_expr(v)
          None => "\"\""
        }
        let else_ = match a.else_val {
          Some(v) => print_expr(v)
          None => "\"\""
        }
        guard option_name(a.name) is Some(opt) else {
          raise NoSpelling(
            what="a conditional `\{a.name}` attribute",
            help="a conditional attribute is written `~name: if cond | a | b`, and this name cannot be written as a name",
          )
        }
        opts.push("~\{opt}: if \{print_expr(a.cond_val)} | \{then_} | \{else_}")
      }
      RawHtml(val~) => opts.push("~dangerously_inner_html: \{print_opt(val)}")
      SafeHtml(val~) => opts.push("~inner_html: \{print_opt(val)}")
      RawMarkdown(val~) => opts.push("~inner_md: \{print_opt(val)}")
      SafeSvg(val~) => opts.push("~inner_svg: \{print_opt(val)}")
    }
  }
  match d.bind {
    Some(b) => opts.push("~bind: \{print_expr(b.target)}")
    None => ()
  }
  // A name the option syntax cannot spell — anything with a colon in it — has
  // no spelling in the new notation, and inventing one here would write a file
  // no reader accepts. The corpus holds exactly one such attribute and it is a
  // typo (`x:each` for `@each`), so the honest answer is to name it and stop.
  if extra is [(name, _), ..] {
    raise NoSpelling(
      what="an attribute named `\{name}`",
      help="an attribute is a name with hyphens written as underscores; a colon has no spelling",
    )
  }
  // A hyphen in a tag is written as an underscore, the same way it is in an
  // attribute name: shrubbery reads `emoji-picker` as three terms.
  guard option_name(d.tag) is Some(tag) else {
    raise NoSpelling(
      what="an element whose tag `\{d.tag}` cannot be written as a name",
      help="a tag is a name with hyphens written as underscores; this one holds something else",
    )
  }
  let head = if opts.is_empty() {
    "@\{tag}"
  } else {
    "@\{tag}(\{opts.join(", ")})"
  }
  let kids = []
  let flat = []
  for c in d.childs {
    let piece = StringBuilder()
    print_node(c, events, indent + "  ", piece)
    if piece.to_string() != "" {
      kids.push(piece.to_string())
      // The same child with NO indent, for the inline form. Trimming the
      // indented one would eat the text's own spacing: `<span>a <x text>… b`
      // has the text nodes `"a "` and `" b"`, and the spaces around the hole
      // are what the page renders. A trim takes them and `equiv` cannot see it,
      // because it compares trees modulo whitespace.
      // A separator prints as the character it is when it sits between its
      // neighbours on one line — `@span{a} @small{b}`. The quoted form the
      // block layout needs is read as layout there and disappears.
      if c is Text(t) && t.val.trim(chars=" \n\t\r") == "" {
        flat.push(" ")
      } else {
        let bare = StringBuilder()
        print_node(c, events, "", bare)
        flat.push(drop_newline(bare.to_string()))
      }
    }
  }
  if kids.is_empty() {
    out.write_string("\{indent}\{head}\n")
    return
  }
  // A body that MIXES text with anything else is written on ONE line, with
  // nothing between the pieces: the text nodes carry their own spacing, so
  // joining them reproduces the content exactly.
  //
  // Two reasons, and the second is the one that forces it. Whitespace is
  // explicit in the new notation, so a body written across lines has a `"\n"`
  // text node between each pair of children — harmless between block elements,
  // and content between inline ones. And a text node written on a line of its
  // own is a shrubbery GROUP: the `": "` between a hole and a span reads as
  // notation there rather than as text, and the file does not parse.
  //
  // A body of ELEMENTS only keeps its lines. What sits between them was layout
  // in the old file too — the HTML tokenizer made text nodes of it and
  // `anode/whitespace.mbt` took them out again — so writing it as layout here
  // is what it was.
  // A body with TEXT in it is written on one line whatever its children look
  // like. The separator between two inline elements is a space, and a space on
  // a line of its own is layout — the reader cuts it, and the two words run
  // together. `flat_children` is what makes the multi-line ones fit.
  if kids.length() > 0 && (inline || has_text(d.childs)) {
    out.write_string(
      "\{indent}\{head}{\{flat_children(d.childs, events).join("")}}\n",
    )
    return
  }
  if kids.length() > 0 && all_one_line(kids) && kids.length() == 1 {
    out.write_string("\{indent}\{head}{\{flat.join("")}}\n")
    return
  }
  out.write_string("\{indent}\{head}{\n")
  for k in kids {
    out.write_string(k)
  }
  out.write_string("\{indent}}\n")
}

///|
/// Whether a printed child is one line — so it can sit inside its parent's
/// braces instead of under them.
fn is_one_line(s : String) -> Bool {
  let body = s.trim(chars=" \n")
  body != "" && !body.contains("\n")
}

///|
/// One printed child with its trailing newline removed and nothing else.
fn drop_newline(s : String) -> String {
  if s.has_suffix("\n") {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// Whether a body has any text in it, which is what decides whether the
/// whitespace between its children is content or layout.
fn has_text(childs : Array[@anode.ANode]) -> Bool {
  for c in childs {
    match c {
      // Every text node that survived the condensing pass, INCLUDING one that
      // is only a space: that space separates the two inline elements around
      // it, and a body written across lines cannot hold one.
      Text(_) => return true
      RenderText(_) => return true
      _ => ()
    }
  }
  false
}

///|
/// Whether every printed child is one line.
fn all_one_line(kids : Array[String]) -> Bool {
  for k in kids {
    if !is_one_line(k) {
      return false
    }
  }
  true
}

///|
/// The attribute list, whichever representation the element collapsed to.
fn attr_items(attrs : @anode.Attrs) -> Array[@anode.AttrItem] {
  match attrs {
    DynAttrs(items) => items
    ConstAttrs(map) => {
      let out = []
      for name, lit in map {
        out.push(@anode.AttrItem::ConstA(name~, val=@tutuca.Expr::lit(lit)))
      }
      out
    }
  }
}

///|
/// The option name an attribute is written as: an underscore is a hyphen, so a
/// hyphen comes back as an underscore, and case is preserved (`viewBox`).
///
/// `None` for a name that round trip would not survive — one holding a colon,
/// a dot, or anything else `~name:` cannot spell.
fn option_name(name : String) -> String? {
  guard name.length() > 0 else { return None }
  guard name[0] is ('a'..='z' | 'A'..='Z') else { return None }
  let out = StringBuilder()
  for c in name {
    match c {
      '-' => out.write_char('_')
      'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => out.write_char(c)
      _ => return None
    }
  }
  Some(out.to_string())
}

///|
fn print_opt(val : @tutuca.Expr?) -> String raise NoSpelling {
  match val {
    Some(v) => print_expr(v)
    None =>
      raise NoSpelling(
        what="a markup directive whose value did not parse",
        help="fix the value in the `.html` file before converting it",
      )
  }
}

///|
fn eid_of(val : @tutuca.Expr) -> Int? {
  match val {
    ELit(lit=LNum(n), ..) => Some(n.to_int())
    _ => None
  }
}

///|
fn handlers_at(
  events : Array[@anode.NodeEvents],
  id : Int,
) -> Array[@anode.NodeEvent] {
  for e in events {
    if e.id == id {
      // The write-back a `~bind:` registers is part of the bind, not a handler
      // written beside it. Printing it as `~on_input:` would give the element
      // an event it never declared — and would put `data-eid` where the first
      // handler was rather than after the mirrored property.
      let out = []
      for h in e.handlers {
        if !(h.binding is Some(BindPending)) {
          out.push(h)
        }
      }
      return out
    }
  }
  []
}

///|
/// Every child printed with no layout of its own, for a body that has to sit on
/// one line. Nesting stays inline all the way down: a child printed across
/// lines cannot be spliced into a line.
fn flat_children(
  childs : Array[@anode.ANode],
  events : Array[@anode.NodeEvents],
) -> Array[String] raise NoSpelling {
  let out = []
  for c in childs {
    if c is Text(t) && t.val.trim(chars=" \n\t\r") == "" {
      out.push(" ")
      continue
    }
    let piece = StringBuilder()
    print_node(c, events, "", piece, inline=true)
    // A newline left in a piece is the line ending of a node with no `inline`
    // form of its own — a macro call, a fragment's children — and the spaces
    // after it are that printer's indentation. Both are layout: on one line
    // they are neither a separator nor content, and a stray one splits the
    // body into pieces the reader then counts.
    let text = strip_layout(piece.to_string())
    if text != "" {
      out.push(text)
    }
  }
  out
}

///|
/// One printed piece with its line breaks and the indentation that followed
/// them removed, so it can be spliced into a line.
fn strip_layout(s : String) -> String {
  let out = StringBuilder()
  let cs = s.to_array()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '\n' {
      i = i + 1
      while i < cs.length() && cs[i] == ' ' {
        i = i + 1
      }
    } else {
      out.write_char(cs[i])
      i = i + 1
    }
  }
  out.to_string()
}
