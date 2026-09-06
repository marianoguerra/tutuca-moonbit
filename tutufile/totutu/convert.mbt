// The whole file: five sections, in order, from what the splitter parsed.

///|
/// What a conversion produced.
pub(all) struct Converted {
  /// The `.tutu` text. Empty when anything was refused — a partial file is
  /// worse than none, because it compiles.
  text : String
  /// Every construct the converter could not spell, one line each.
  refusals : Array[String]
}

///|
/// An `.html` view file, as the `.tutu` file that replaces it.
///
/// `name` is what `gen --name` would supply: a file that declares one unnamed
/// component has no name of its own, and a `.tutu` file always names its
/// components.
pub fn convert(html : String, name~ : String) -> Converted {
  let refusals = []
  let file = @viewfile.split_file(html, name~) catch {
    e => {
      refusals.push("the file did not split: \{e.message()}")
      return { text: "", refusals, }
    }
  }
  let out = StringBuilder()
  let add = (r : NoSpelling) => {
    let NoSpelling(what~, help~) = r
    refusals.push("\{what} — \{help}")
  }
  section_spec(file, out) catch {
    e => add(e)
  }
  section_logic(file, out) catch {
    e => add(e)
  }
  section_view(file, name, out) catch {
    e => add(e)
  }
  section_fixtures(file, out) catch {
    e => add(e)
  }
  section_tests(file, out) catch {
    e => add(e)
  }
  if !refusals.is_empty() {
    return { text: "", refusals, }
  }
  { text: out.to_string(), refusals, }
}

///|
fn section_spec(
  file : @viewfile.ViewFile,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !file.state.is_empty() else { return }
  out.write_string("spec:\n")
  let mut first = true
  for def in file.state {
    if !first {
      out.write_string("\n")
    }
    first = false
    print_spec(def, root=def.component == file.root, out)
    // A `struct` or an `enum` is a declaration of the FILE rather than of the
    // component's body, which is where the old block put it too.
    for t in def.types {
      out.write_string("\n")
      print_user_ty(t, out)
    }
  }
  out.write_string("\n")
}

///|
fn section_logic(
  file : @viewfile.ViewFile,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !file.scripts.is_empty() else { return }
  out.write_string("logic:\n")
  let mut first = true
  for s in file.scripts {
    let comp = if s.comp != "" {
      s.comp
    } else if file.state.length() == 1 {
      file.state[0].component
    } else if file.components.length() == 1 {
      file.components[0].name
    } else {
      raise NoSpelling(
        what="a script block with no `for=` in a file that declares several components",
        help="a `.tutu` file names the component each handler belongs to, and this block does not say which one",
      )
    }
    let decls = @tscript.parse_script(s.block.text) catch {
      _ =>
        raise NoSpelling(
          what="a script block that does not parse",
          help="fix it in the `.html` file before converting",
        )
    }
    if !first {
      out.write_string("\n")
    }
    first = false
    print_logic(comp, decls, schema_for(file, comp), out)
  }
  out.write_string("\n")
}

///|
fn schema_for(file : @viewfile.ViewFile, comp : String) -> @statedef.StateDef? {
  for d in file.state {
    if d.component == comp {
      return Some(d)
    }
  }
  None
}

///|
fn section_view(
  file : @viewfile.ViewFile,
  name : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !file.components.is_empty() || !file.macros.is_empty() else { return }
  out.write_string("view:\n")
  let scope = MacroText::of(file.macros)
  let mut first = true
  for m in file.macros {
    if !first {
      out.write_string("\n")
    }
    first = false
    print_macro(m, scope, out)
  }
  for set in file.components {
    if set.common_style != "" {
      if !first {
        out.write_string("\n")
      }
      first = false
      print_style(set.common_style, "", out)
    }
    if set.global_style != "" {
      if !first {
        out.write_string("\n")
      }
      first = false
      print_style(set.global_style, "~global", out)
    }
    for v in set.views {
      if !first {
        out.write_string("\n")
      }
      first = false
      // A `.tutu` file always names its components, so a view whose template
      // carried no name has to be given one. The SPEC block is the first place
      // to look — a file declaring one component and one unnamed template is
      // that component's view, whatever the file happens to be called — and
      // `gen --name` only decides it when the spec does not.
      let comp = if set.name != "" {
        set.name
      } else if file.state.length() == 1 {
        file.state[0].component
      } else {
        name
      }
      let declared = if v.name == "main" { comp } else { comp + "." + v.name }
      let (tree, events) = compile_view(v, scope)
      let body = print_view(tree, events, "    ")
      let style = StringBuilder()
      if v.style != "" {
        print_style(v.style, "", style, indent="    ")
      }
      // A view with nothing in it is declared with no block: `:` and nothing
      // under it is not a declaration, and `<template id="X"></template>` is a
      // real thing in the corpus that renders nothing.
      guard body != "" || style.to_string() != "" else {
        out.write_string("  \{declared}\n")
        continue
      }
      out.write_string("  \{declared}:\n")
      out.write_string(style.to_string())
      out.write_string(body)
    }
  }
  out.write_string("\n")
}

///|
/// A `<style>` block, as the `@style{…}` it becomes.
fn print_style(
  css : String,
  opts : String,
  out : StringBuilder,
  indent? : String = "  ",
) -> Unit raise NoSpelling {
  // The body is written AS IT IS. At-notation owns `@`, `{` and `}`, but its
  // brace matching is what CSS already does — a rule's braces are balanced —
  // and `@media` is `@` followed by a letter, which reads as text. Escaping
  // them was the mistake: it produced `@}`, and see below.
  //
  // On ONE line, and that is not tidiness. A style block's body arrives as one
  // text piece per line and both readers join them with nothing between, so
  // `color: red` above `background: blue` would come back as one declaration
  // that is neither. Collapsing first is what makes the join lossless.
  let body = collapse_css(css)
  // `marianoguerra/shrubbery@0.1.0` stack-overflows on a `@` whose next
  // character is the closing brace — `@style{a@}` and `@style{@@}` both exit
  // 139, while `@style{a@@b}` and `@media` do not. It is a position, not an
  // escape, so the refusal is that position and nothing wider: a file carrying
  // one segfaults every reader of `.tutu` text, and emitting a file that
  // crashes the parser is worse than not emitting one.
  guard !body.has_suffix("@") else {
    raise NoSpelling(
      what="a style block whose CSS ends in `@`",
      help="`marianoguerra/shrubbery@0.1.0` stack-overflows on a `@` immediately before a closing brace — convert this style block by hand until that is fixed upstream",
    )
  }
  // Unbalanced braces would close the block early and take the rest of the view
  // with them. CSS balances its own; a fragment might not.
  guard balanced(body) else {
    raise NoSpelling(
      what="a style block whose braces are not balanced",
      help="at-notation ends a body at the brace that matches its opening one, so a stylesheet with a stray `{` or `}` would take the rest of the view with it",
    )
  }
  let head = if opts == "" { "@style" } else { "@style(\{opts})" }
  out.write_string("\{indent}\{head}{\{body}}\n")
}

///|
/// Whether every `{` in the text has its `}`.
fn balanced(s : String) -> Bool {
  let mut depth = 0
  for c in s {
    if c == '{' {
      depth = depth + 1
    } else if c == '}' {
      depth = depth - 1
      if depth < 0 {
        return false
      }
    }
  }
  depth == 0
}

///|
/// A stylesheet's whitespace collapsed to single spaces. CSS does not care, and
/// the notation cannot carry the line breaks losslessly.
fn collapse_css(css : String) -> String {
  let words = []
  let cur = StringBuilder()
  for c in css {
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
/// One macro, with its parameters and their defaults.
fn print_macro(
  m : @viewfile.MacroDef,
  scope : MacroText,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let params = []
  for k, v in m.defaults {
    params.push("~\{@names.snake_of(k)}: \{macro_arg(v)}")
  }
  let head = if params.is_empty() {
    "macro \{@names.snake_of(m.name)}()"
  } else {
    "macro \{@names.snake_of(m.name)}(\{params.join(", ")})"
  }
  out.write_string("  \{head}:\n")
  // Parsed INSIDE a macro frame, because a `^label` read outside one resolves
  // to nothing and the value is dropped — which is how a macro body converted
  // to an element with no content.
  //
  // Each parameter is bound to a SENTINEL rather than to itself: binding
  // `label` to `^label` makes the value parser substitute it into itself for
  // ever. A `$name` parses, cannot be confused with anything the corpus writes,
  // and `print_expr` reads the parameter's own name back out of it.
  let px = @anode.ParseContext::new()
  let tree = @anode.ANode::parse(sentinel_params(m.source), px)
  guard tree is Some(tree) else {
    raise NoSpelling(
      what="a macro whose body did not parse (`\{m.name}`)",
      help="fix it in the `.html` file before converting",
    )
  }
  ignore(scope)
  out.write_string(print_view(tree, px.events, "    "))
}

///|
/// A macro's source with every `^name` replaced by the sentinel.
///
/// A text substitution, on text — which is what a macro's body IS on the old
/// path, and the only shape it has before a call site opens a frame for it.
/// Parsing it with a real frame does not work: binding `label` to `^label`
/// substitutes it into itself for ever, and binding it to a value would print
/// the value where the parameter was.
fn sentinel_params(source : String) -> String {
  let out = StringBuilder()
  let cs : Array[Char] = source.iter().collect()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '^' &&
      i + 1 < cs.length() &&
      cs[i + 1] is ('a'..='z' | 'A'..='Z' | '_') {
      out.write_string(macro_sentinel)
      i = i + 1
    } else {
      out.write_char(cs[i])
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// One view, compiled the way the pipeline compiles it, so what is printed is
/// what the renderer would have got.
fn compile_view(
  v : @viewfile.RawView,
  scope : MacroText,
) -> (@anode.ANode, Array[@anode.NodeEvents]) raise NoSpelling {
  let view = @anode.View::new(v.name, raw_view=v.source)
  let px = @anode.ParseContext::new()
  view.compile(px, scope) catch {
    _ =>
      raise NoSpelling(
        what="a view that did not compile (`\{v.name}`)",
        help="fix it in the `.html` file before converting",
      )
  }
  guard view.anode is Some(tree) else {
    raise NoSpelling(
      what="a view with no nodes (`\{v.name}`)",
      help="an empty view has nothing to convert",
    )
  }
  (tree, px.events)
}

///|
fn section_fixtures(
  file : @viewfile.ViewFile,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !file.init.is_empty() else { return }
  out.write_string("fixtures:\n")
  let mut first = true
  for pair in file.init {
    if !first {
      out.write_string("\n")
    }
    first = false
    print_fixture(pair.1, out)
  }
  out.write_string("\n")
}

///|
fn section_tests(
  file : @viewfile.ViewFile,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  guard !file.tests.is_empty() else { return }
  out.write_string("tests:\n")
  let mut first = true
  for s in file.tests {
    if !first {
      out.write_string("\n")
    }
    first = false
    print_scene(s, out)
  }
}

///|
/// A macro scope over the file's own macro templates.
priv struct MacroText {
  by_name : Map[String, @anode.Macro]
}

///|
fn MacroText::of(defs : Array[@viewfile.MacroDef]) -> MacroText {
  let by_name : Map[String, @anode.Macro] = Map([])
  for d in defs {
    by_name[d.name] = { defaults: d.defaults, raw_view: d.source, }
  }
  { by_name, }
}

///|
impl @anode.MacroScope for MacroText with fn lookup_macro(self, name) {
  self.by_name.get(name)
}

///|
/// Whether a name is a component name: a type, so PascalCase.
pub fn is_type_name(name : String) -> Bool {
  @names.is_type_name(name)
}

///|
/// The component name a file's basename suggests: `counter` is `Counter`, and
/// `todo_list` is `TodoList`.
pub fn pascal_of(name : String) -> String {
  let out = StringBuilder()
  let mut up = true
  for c in name {
    if c is ('_' | '-' | '.') {
      up = true
    } else if up && c is ('a'..='z') {
      out.write_char(Int::unsafe_to_char(c.to_int() - 32))
      up = false
    } else {
      out.write_char(c)
      up = false
    }
  }
  out.to_string()
}
