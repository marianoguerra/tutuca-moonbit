// One view, printed in the aligned notation.

///|
/// The options that stay `~`-prefixed: tutuca's DIRECTIVES.
///
/// Law 4 puts the sigil exactly on the seam between the two languages, so this
/// table is the seam written down. A plain declaration is an HTML attribute and
/// reads the same in Shrubbery HTML; a `~keyword` is something only tutuca
/// answers, and every one of them is here.
///
/// `on_*` is a prefix rather than an entry, because an event is named after the
/// DOM event it listens to and that set is open.
fn is_directive(name : String) -> Bool {
  if name.has_prefix("on_") {
    return true
  }
  match name {
    // render-time options
    "when" | "enrich_with" | "loop_with" | "push_view" | "as" | "bind" => true
    // an event's modifiers
    "key"
    | "send"
    | "cancel"
    | "prevent"
    | "stop"
    | "ctrl"
    | "cmd"
    | "meta"
    | "alt" => true
    // a style block's scope
    "global" => true
    _ => false
  }
}

///|
/// A string in shrubbery's spelling, which is JSON's.
pub fn quote(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// One view's body, indented under its declaration.
pub fn print_view(
  decl : @tutufile.Decl,
  indent : String,
  macros? : Array[String] = [],
  css? : Bool = false,
) -> String raise @sh.ExError {
  let out = StringBuilder()
  for g in @sh.body_groups(decl) {
    print_group(g, indent, out, macros~, css~)
  }
  out.to_string()
}

///|
/// One group of a body, as a run of children.
///
/// ONE CHILD PER LINE, always. A run on one line is legal and reads well when
/// nothing in it has children, but a block runs to the end of its line -- so an
/// emitter that inlined a run would eventually write `p(): "a " strong(): "b"
/// "!"`, where the `"!"` is a child of the `strong` rather than a sibling of
/// it. Refusing to inline costs lines and makes that shape unreachable from
/// anything this writes. `marianoguerra/shrubbery-html`'s emitter takes the
/// same decision for the same reason.
fn print_group(
  g : @ast.Node,
  indent : String,
  out : StringBuilder,
  macros? : Array[String] = [],
  css? : Bool = false,
) -> Unit raise @sh.ExError {
  guard g.it is Group(parts) && parts.length() > 0 else { return }
  // Consecutive text pieces are ONE string. A body holding an escape arrives as
  // several pieces -- `@p{a@"@"b}` is `a`, `@`, `b` -- and the DOM has no such
  // distinction, so the reader merges them. Merging here too is what makes the
  // two trees compare equal.
  let run = StringBuilder()
  let flush = fn() -> Unit {
    let t = run.to_string()
    run.reset()
    if t != "" {
      out.write_string(indent + quote(t) + "\n")
    }
  }
  let mut i = 0
  while i < parts.length() {
    match parts[i].it {
      Lit(Str(t)) => {
        run.write_string(t)
        i = i + 1
      }
      // A hole. `@(x)` and `(x)` are the same tree -- the `@` is consumed by
      // the lexer -- so the sigil is written back on, because that is the
      // spelling every view in the corpus and every line of the documentation
      // uses.
      Parens(_) => {
        flush()
        // `to_source()` reproduces the `@` the lexer consumed, so it is not
        // written again -- prepending one spells `@@`, which is an error in
        // the notation rather than a doubled sigil.
        let src = parts[i].to_source().trim_start(chars="@").to_owned()
        out.write_string(indent + "@" + src + "\n")
        i = i + 1
      }
      Id(word) => {
        flush()
        let mut take = 1
        if i + take < parts.length() && parts[i + take].it is Parens(_) {
          take = take + 1
        }
        while i + take < parts.length() &&
              parts[i + take].it is (Kw(_) | Block(_)) {
          take = take + 1
        }
        print_element(word, parts[i:i + take].to_owned(), indent, out, macros~, css~)
        i = i + take
      }
      _ =>
        raise @sh.ExError(
          message="this is not markup",
          help="a view holds elements, text and `@(…)` holes",
          span=@sh.span_of(g),
        )
    }
  }
  flush()
}
