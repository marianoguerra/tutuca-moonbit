// An element, a form or a macro call: one shape, and the name decides nothing
// here. The printer treats them alike because the notation does -- what varies
// is only whether the arguments are attributes or a binder, and both print as
// the source they were written as.

///|
/// The raw-text elements, whose body is text rather than markup.
///
/// `style` is the one a view writes. The rest are here because the reader will
/// take them from `@html/names` and this is the same set: a body that is text
/// must be printed as `@{…}` and not as string literals, or its braces and its
/// `@`s change meaning.
fn is_raw_text(name : String) -> Bool {
  name is ("style" | "script")
}

///|
/// One element and everything under it.
fn print_element(
  word : String,
  parts : Array[@ast.Node],
  indent : String,
  out : StringBuilder,
  macros? : Array[String] = [],
) -> Unit raise @sh.ExError {
  let (args, body) = @sh.split_call(parts)
  // A MACRO CALL's arguments keep their sigil. They are neither HTML
  // attributes nor render directives but arguments to a form tutuca defines,
  // and `expand_macro` reads only `AKw` and `AFlag` -- so stripping the `~`
  // would write a call whose parameters nothing binds.
  let keep = macros.contains(word)
  let head = indent + word + "(" + print_args(args, keep) + ")"
  if body.length() == 0 {
    out.write_string(head + "\n")
    return
  }
  // A raw-text body stays raw. `@{…}` is shrubbery's indentation-stripping
  // literal block, which is what this needs and what Shrubbery HTML uses for
  // the same elements -- and it is why the CSS in a `style` block needs no
  // escaping: at-notation ends its body at the MATCHING brace.
  if is_raw_text(word) {
    out.write_string(head + ": @{" + raw_text(body) + "}\n")
    return
  }
  // A comment's body is text, and `comment(" x ")` is how Shrubbery HTML
  // spells it: the string carries its own spaces, so nothing has to remember
  // that a comment's edges are significant.
  if word == "comment" {
    out.write_string(head + ": " + quote(raw_text(body)) + "\n")
    return
  }
  out.write_string(head + ":\n")
  for g in body {
    print_group(g, indent + "  ", out, macros~)
  }
}

///|
/// A call's arguments, in the aligned spelling.
///
/// Law 4 is applied here and nowhere else: a `~keyword` the directive table
/// knows keeps its sigil, and everything else loses it and becomes a plain
/// declaration -- which is byte-identical to what Shrubbery HTML writes.
fn print_args(args : Array[@ast.Node], keep : Bool) -> String {
  let out = []
  for a in args {
    out.push(print_arg(a, keep))
  }
  out.join(", ")
}

///|
/// One argument.
fn print_arg(a : @ast.Node, keep : Bool) -> String {
  guard a.it is Group(parts) && parts.length() >= 1 else {
    return joined(a.children())
  }
  guard parts[0].it is Kw(name) else { return joined(parts) }
  if keep || is_directive(name) {
    return joined(parts)
  }
  // `~class: "x"` becomes `class: "x"`. The rest of the group is printed as it
  // was written, so the value -- which may be any expression -- is carried
  // across verbatim rather than reconstructed.
  name + joined(parts[1:].to_owned()).trim_start(chars=" ").to_owned()
}

///|
/// The source of several terms, as written.
///
/// Per TERM rather than per group, because a group's own `to_source()` carries
/// the punctuation that SEPARATES it from its neighbours -- the `,` after it and
/// the `)` that closed the list -- and pasting those back in writes `inc))` and
/// `it.kid,,`. A term's source is just the term.
fn joined(parts : Array[@ast.Node]) -> String {
  let out = StringBuilder()
  for p in parts {
    out.write_string(p.to_source())
  }
  out.to_string().trim(chars=" ").to_owned()
}

///|
/// The text of a raw-text body, joined.
fn raw_text(body : Array[@ast.Node]) -> String {
  let out = StringBuilder()
  for g in body {
    guard g.it is Group(parts) else { continue }
    for p in parts {
      match p.it {
        Lit(Str(t)) => out.write_string(t)
        // The ALIGNED spelling of the same body: `@{…}` arrives as a `Parens`
        // holding one `Group` holding one `Brackets` of string pieces. Reading
        // only the flat literal answered "" for every style block already
        // converted, so a second run would have emptied all of them. The
        // round-trip check refuses on that, so nothing was written -- but a
        // converter that fails safe is not the same as one that is right.
        Parens(gs) =>
          for inner in gs {
            guard inner.it is Group(one) else { continue }
            for it in one {
              guard it.it is Brackets(items) else { continue }
              for item in items {
                if item.it is Group(pieces) {
                  for piece in pieces {
                    if piece.it is Lit(Str(t)) {
                      out.write_string(t)
                    }
                  }
                }
              }
            }
          }
        _ => ()
      }
    }
  }
  out.to_string()
}
