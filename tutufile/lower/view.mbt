// The `view:` section, printed as the templates the view compiler reads.
//
// At-notation is already a tree of elements, attributes and content, so this
// is a printer rather than a translator: `@div(~class: "x"){…}` and
// `<div class="x">…</div>` are the same node written twice.

///|
/// Print one view as its `<template>`.
pub fn print_view(
  decl : @tutufile.Decl,
  out : StringBuilder,
  macros? : Array[String] = [],
) -> Unit raise ExError {
  // `Note.edit` is one component and one of its views; the old notation
  // spells the same pair `Note:edit`.
  let id = decl.name.replace(old=".", new=":")
  out.write_string("<template id=\"\{id}\">\n")
  for g in body_groups(decl) {
    print_content(g, out, "  ", Map([]), macros~)
  }
  out.write_string("</template>\n\n")
}

///|
/// A value read in a VIEW, where a bare name is a scope binding.
///
/// A property is `it.x`, a method is `name(…)`, and what is left — a name with
/// nothing on it — is something a loop or an enricher put in scope. The old
/// notation spells that `@name`, so the sigil goes back on at the last moment
/// rather than being carried through the reader.
fn bound(ex : Ex, renames : Map[String, String]) -> Ex {
  let ex = rename_ex(ex, renames)
  bind_names(ex)
}

///|
fn bind_names(ex : Ex) -> Ex {
  match ex {
    EName(n) =>
      if n.has_prefix("@") || n == "true" || n == "false" || n == "null" {
        ex
      } else {
        EName("@" + n)
      }
    EMember(EName(n), m) =>
      if n.has_prefix("@") || n == "e" {
        ex
      } else {
        EMember(EName("@" + n), m)
      }
    EBin(op, a, b) => EBin(op, bind_names(a), bind_names(b))
    EUn(op, a) => EUn(op, bind_names(a))
    EIf(c, a, b) => EIf(bind_names(c), bind_names(a), bind_names(b))
    EIndex(a, b) => EIndex(bind_names(a), bind_names(b))
    ETemplate(parts) => {
      let out = []
      for p in parts {
        out.push(
          match p {
            TText(t) => TText(t)
            THole(h) => THole(bind_names(h))
          },
        )
      }
      ETemplate(out)
    }
    _ => ex
  }
}

///|
/// One item of an at-notation body: text, a hole, or an element.
fn print_content(
  group : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 else { return }
  match parts[0].it {
    // plain text
    Lit(Str(text)) => {
      let t = text.trim(chars=" \n\t").to_owned()
      if t != "" {
        out.write_string("\{indent}\{escape_text(t)}\n")
      }
    }
    // `@(expr)` — a value with no element around it
    Parens(gs) => {
      guard gs.length() == 1 else { return }
      let ex = bound(read_group(gs[0]), renames)
      out.write_string(
        "\{indent}<x text=\"\{attr_escape(print_ex(ex))}\"></x>\n",
      )
    }
    Id(word) => print_element(word, parts, out, indent, renames, macros~)
    _ =>
      raise ExError(
        message="this is not markup",
        help="a view holds elements, text and `@(…)` holes",
        span=span_of(group),
      )
  }
}

///|
/// An element, a form, or a macro call — they are one shape and the name
/// decides which.
fn print_element(
  word : String,
  parts : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  if macros.contains(word) {
    return print_macro_call(word, parts, out, indent, renames)
  }
  let (raw, body) = split_call(parts)
  match word {
    "show" | "hide" =>
      print_guard(word, args_of(raw), body, out, indent, renames, macros~)
    "each" => print_each(raw, body, out, indent, renames, macros~)
    "render" => print_render(args_of(raw), out, indent, renames)
    "slot" => out.write_string("\{indent}<slot></slot>\n")
    "style" => print_style(args_of(raw), body, out, indent)
    _ => print_tag(word, args_of(raw), body, out, indent, renames, macros~)
  }
}

///|
/// A macro call, which is an element call whose name the file declares.
///
/// The old notation spells one `<x:name>` — a tag in a namespace of its own,
/// because markup had no other way to say "this is not an element". Here it is
/// a call like any other, and the only thing that tells it from an element is
/// that the file declares it.
fn print_macro_call(
  name : String,
  parts : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  let (raw, body) = split_call(parts)
  let attrs = []
  for a in args_of(raw) {
    match a {
      // a literal argument passes as a static attribute, the way the old
      // notation's `label="Sale"` did; anything else is bound
      AKw(arg, EStr(text)) =>
        attrs.push("\{attr_name(arg)}=\"\{attr_escape(text)}\"")
      AKw(arg, value) =>
        attrs.push(
          ":\{attr_name(arg)}=\"\{attr_escape(print_ex(bound(value, renames)))}\"",
        )
      _ => ()
    }
  }
  let head = if attrs.is_empty() {
    "x:" + name
  } else {
    "x:" + name + " " + attrs.join(" ")
  }
  if body.is_empty() {
    out.write_string("\{indent}<\{head}></x:\{name}>\n")
    return
  }
  out.write_string("\{indent}<\{head}>\n")
  for g in body {
    print_content(g, out, indent + "  ", renames, macros~)
  }
  out.write_string("\{indent}</x:\{name}>\n")
}

///|
/// A plain element.
fn print_tag(
  tag : String,
  args : Array[Arg],
  body : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  let attrs = []
  for a in args {
    match a {
      AKw(name, value) => attrs.push(print_attr(name, value, renames))
      AFlag(name) => attrs.push(attr_name(name))
      AField(name, _) =>
        raise ExError(
          message="`\{name}:` is not an attribute",
          help="write `~\{name}: <value>` — an attribute is an option of the element",
          span=@report.Span::at(0),
        )
      APos(_) =>
        raise ExError(
          message="an element takes named attributes only",
          help="write `~class: \"x\"` rather than a bare value",
          span=@report.Span::at(0),
        )
    }
  }
  let head = if attrs.is_empty() { tag } else { tag + " " + attrs.join(" ") }
  if body.is_empty() {
    out.write_string("\{indent}<\{head}></\{tag}>\n")
    return
  }
  out.write_string("\{indent}<\{head}>\n")
  for g in body {
    print_content(g, out, indent + "  ", renames, macros~)
  }
  out.write_string("\{indent}</\{tag}>\n")
}

///|
/// One attribute: a literal stays static, everything else is bound.
fn print_attr(
  name : String,
  value : Ex,
  renames : Map[String, String],
) -> String raise ExError {
  if name.has_prefix("on_") {
    let event = name[3:].to_owned()
    return "@on.\{event}=\"\{attr_escape(print_action(value, renames))}\""
  }
  match name {
    "bind" =>
      return "@bind=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    "push_view" =>
      return "@push-view=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    "inner_html" =>
      return "@setinnerhtml=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    // The one construct whose value reaches the DOM unparsed, and the only
    // attribute here whose name says so out loud.
    "dangerously_inner_html" =>
      return "@dangerouslysetinnerhtml=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    "inner_md" =>
      return "@setinnermd=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    "inner_svg" =>
      return "@setinnersvg=\"\{attr_escape(print_ex(rename_ex(value, renames)))}\""
    _ => ()
  }
  let attr = attr_name(name)
  match value {
    EStr(s) => "\{attr}=\"\{attr_escape(s)}\""
    other => ":\{attr}=\"\{attr_escape(print_ex(bound(other, renames)))}\""
  }
}

///|
/// An event's value: a handler call, or a property action.
fn print_action(
  value : Ex,
  renames : Map[String, String],
) -> String raise ExError {
  let value = rename_ex(value, renames)
  match value {
    EName(handler) => handler
    ECall(EName(handler), args) => {
      let parts = [handler]
      for a in positional(args) {
        parts.push(print_ex(a))
      }
      parts.join(" ")
    }
    EBin(":=", place, v) => print_place(place) + " = " + print_ex(v)
    ECall(EMember(recv, op), args) => {
      guard collection_op(op) is Some(word) else {
        raise ExError(
          message="`\{op}` is not a property action",
          help="the actions are `push`, `insert_at`, `set_at`, `delete_at`, `add`, `remove` and `toggle`",
          span=@report.Span::at(0),
        )
      }
      let parts = [print_place(recv) + "." + word]
      for a in positional(args) {
        parts.push(print_ex(a))
      }
      parts.join(" ")
    }
    _ =>
      raise ExError(
        message="an event names a handler or writes a property",
        help="write `~on_click: inc`, or `~on_input: it.query := e.value`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// `@show(c){…}` / `@hide(c){…}`, which annotate the element they wrap.
fn print_guard(
  word : String,
  args : Array[Arg],
  body : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  let pos = positional(args)
  guard pos.length() == 1 else {
    raise ExError(
      message="`@\{word}` takes one condition",
      help="write `@\{word}(<condition>){ … }`",
      span=@report.Span::at(0),
    )
  }
  guard body.length() == 1 else {
    raise ExError(
      message="`@\{word}` wraps one element here",
      help="the old notation puts the condition ON an element, so give this one element to wrap",
      span=@report.Span::at(0),
    )
  }
  let cond = print_ex(bound(pos[0], renames))
  print_with_extra(
    body[0],
    out,
    indent,
    renames,
    "@\{word}=\"\{attr_escape(cond)}\"",
    macros~,
  )
}

///|
/// `@each(item, i in xs, ~when: f){…}` — the loop's bindings are what the
/// renderer hands the filters, so the body is printed under their old names.
fn print_each(
  raw : Array[@ast.Node],
  body : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  macros? : Array[String] = [],
) -> Unit raise ExError {
  let (names, seq, after) = split_binder(raw)
  let args = args_of(raw[after:].to_owned())
  let inner : Map[String, String] = Map([])
  for k in renames {
    inner[k.0] = k.1
  }
  if names.length() > 0 {
    inner[names[0]] = "@value"
  }
  if names.length() > 1 {
    inner[names[1]] = "@key"
  }
  let extra = ["@each=\"\{attr_escape(print_ex(rename_ex(seq, renames)))}\""]
  match kw_arg(args, "when") {
    Some(EName(f)) => extra.push("@when=\"\{f}\"")
    Some(_) =>
      raise ExError(
        message="`~when` names a filter",
        help="declare it with `pred <name>(item, i)` in the logic section",
        span=@report.Span::at(0),
      )
    None => ()
  }
  match kw_arg(args, "enrich_with") {
    Some(EName(f)) => extra.push("@enrich-with=\"\{f}\"")
    Some(_) => ()
    None => ()
  }
  match kw_arg(args, "loop_with") {
    Some(EName(f)) => extra.push("@loop-with=\"\{f}\"")
    Some(_) => ()
    None => ()
  }
  guard body.length() == 1 else {
    raise ExError(
      message="`@each` repeats one element here",
      help="the old notation puts the loop ON an element, so give this one element to repeat",
      span=@report.Span::at(0),
    )
  }
  print_with_extra(body[0], out, indent, inner, extra.join(" "), macros~)
}

///|
/// `item in xs`, or `item, i in xs`.
///
/// A comma separates GROUPS inside parentheses, so `item, i in it.pages` is
/// two of them and the binder is not one term sequence but several. This is
/// the one place a view reads NAMES rather than values — the loop introduces
/// them, which is what makes a member read on one checkable.
fn split_binder(
  raw : Array[@ast.Node],
) -> (Array[String], Ex, Int) raise ExError {
  let names = []
  let mut g = 0
  while g < raw.length() {
    guard raw[g].it is Group(parts) else { break }
    let mut i = 0
    let mut saw_in = false
    while i < parts.length() {
      match parts[i].it {
        Id("in") => {
          saw_in = true
          i = i + 1
          break
        }
        Id(n) => {
          names.push(n)
          i = i + 1
        }
        _ => i = i + 1
      }
    }
    if saw_in {
      guard names.length() > 0 && i < parts.length() else { break }
      return (names, read_ex(parts[i:]), g + 1)
    }
    g = g + 1
  }
  raise ExError(
    message="`@each` needs `<name> in <sequence>`",
    help="write `@each(item in it.items){ … }`, or `@each(item, i in it.items)`",
    span=if raw.length() > 0 { span_of(raw[0]) } else { @report.Span::at(0) },
  )
}

///|
/// `@render(value, ~as: view)`.
fn print_render(
  args : Array[Arg],
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise ExError {
  let pos = positional(args)
  guard pos.length() == 1 else {
    raise ExError(
      message="`@render` takes one value",
      help="write `@render(it.item)`",
      span=@report.Span::at(0),
    )
  }
  let value = print_ex(rename_ex(pos[0], renames))
  let mut tail = ""
  match kw_arg(args, "as") {
    Some(EStr(v)) => tail = " as=\"\{v}\""
    Some(other) => tail = " as=\"\{attr_escape(print_ex(other))}\""
    None => ()
  }
  out.write_string("\{indent}<x render=\"\{attr_escape(value)}\"\{tail}></x>\n")
}

///|
/// `@style{…}` / `@style(~global){…}`.
fn print_style(
  args : Array[Arg],
  body : Array[@ast.Node],
  out : StringBuilder,
  indent : String,
) -> Unit {
  let mut mark = ""
  for a in args {
    if a is AFlag("global") {
      mark = " data-global"
    }
  }
  let css = []
  for g in body {
    guard g.it is Group(parts) && parts.length() == 1 else { continue }
    match parts[0].it {
      Lit(Str(t)) => css.push(t)
      _ => ()
    }
  }
  out.write_string("\{indent}<style\{mark}>\{css.join("")}</style>\n")
}

///|
/// Print an element with directives the form around it contributed.
fn print_with_extra(
  group : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
  extra : String,
  macros? : Array[String] = [],
) -> Unit raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 && parts[0].it is Id(tag) else {
    raise ExError(
      message="this form wraps an element",
      help="give it one element to annotate",
      span=span_of(group),
    )
  }
  let (raw, body) = split_call(parts)
  let args = args_of(raw)
  let attrs = [extra]
  for a in args {
    match a {
      AKw(name, value) => attrs.push(print_attr(name, value, renames))
      AFlag(name) => attrs.push(attr_name(name))
      _ => ()
    }
  }
  let head = tag + " " + attrs.join(" ")
  if body.is_empty() {
    out.write_string("\{indent}<\{head}></\{tag}>\n")
    return
  }
  out.write_string("\{indent}<\{head}>\n")
  for g in body {
    print_content(g, out, indent + "  ", renames, macros~)
  }
  out.write_string("\{indent}</\{tag}>\n")
}

///|
/// An at-notation call's argument groups and its body.
///
/// The groups come back unparsed because one form reads NAMES out of them:
/// `@each(item in it.items)` binds `item`, and a binder is not a value.
fn split_call(parts : Array[@ast.Node]) -> (Array[@ast.Node], Array[@ast.Node]) {
  let args = []
  let body = []
  let mut i = 1
  while i < parts.length() {
    match parts[i].it {
      Parens(gs) =>
        for g in gs {
          match body_of(g) {
            Some(items) =>
              for item in items {
                body.push(item)
              }
            None => args.push(g)
          }
        }
      _ => ()
    }
    i = i + 1
  }
  (args, body)
}

///|
/// The argument groups, read as values.
fn args_of(groups : Array[@ast.Node]) -> Array[Arg] raise ExError {
  read_args(groups)
}

///|
/// The bracketed content list an at-notation body arrives as.
fn body_of(group : @ast.Node) -> Array[@ast.Node]? {
  guard group.it is Group(parts) && parts.length() == 1 else { return None }
  guard parts[0].it is Brackets(items) else { return None }
  Some(items)
}

///|
/// An underscore is a hyphen; case is preserved.
fn attr_name(name : String) -> String {
  let out = StringBuilder()
  for c in name {
    if c == '_' {
      out.write_char('-')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn escape_text(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '&' => out.write_string("&amp;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn attr_escape(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '"' => out.write_string("&quot;")
      '<' => out.write_string("&lt;")
      '&' => out.write_string("&amp;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}
