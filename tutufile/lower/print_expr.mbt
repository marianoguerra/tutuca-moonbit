// An expression printed back into the notation the slot and script parsers
// read.
//
// Everything is parenthesised that could be: the target language requires
// parentheses wherever precedence would be implicit, and a printer that
// guessed which ones were unnecessary would be a second precedence table to
// keep in step with the first.

///|
/// Print an expression as tutuca source.
pub fn print_ex(ex : @sh.Ex) -> String raise @sh.ExError {
  match ex {
    // A negative number is parenthesised for the same reason a negation is:
    // an argument list is space-separated in the old notation, so
    // `send 'nudge' -1` reads as a subtraction with nothing after it.
    @sh.ENum(n) => if n < 0 { "(" + num_text(n) + ")" } else { num_text(n) }
    @sh.EStr(s) => quote_str(s)
    @sh.EBool(b) => if b { "true" } else { "false" }
    // The absent value has a literal in both notations. `x == none` still
    // folds into the shape predicate below, because that one is total where a
    // comparison against a null is not.
    @sh.ENone => "null"
    @sh.EName(n) => n
    @sh.EIt(f) => "." + f
    @sh.EState(f) => "state." + f
    @sh.EDyn(n) => "*" + n
    @sh.EMember(base, m) => print_member(base, m)
    @sh.EIndex(base, k) => print_ex(base) + "[" + print_ex(k) + "]"
    @sh.ECall(callee, args) => print_call(callee, args)
    @sh.EBin(op, a, b) => print_bin(op, a, b)
    @sh.EUn("!", a) => "(not " + print_ex(a) + ")"
    // Parenthesised, because an argument list is space-separated in the old
    // notation and `send 'nudge' -1` reads as a subtraction that never ends.
    // A negation is never ambiguous inside its own parentheses.
    @sh.EUn("-", a) => "(-" + print_ex(a) + ")"
    @sh.EUn(op, _) =>
      raise @sh.ExError(
        message="`\{op}` is not a prefix operator",
        help="the prefix operators are `!` and `-`",
        span=@report.Span::at(0),
      )
    @sh.EIf(c, a, b) =>
      "if " +
      print_ex(c) +
      " { " +
      print_ex(a) +
      " } else { " +
      print_ex(b) +
      " }"
    @sh.ETemplate(parts) => print_template(parts)
    @sh.EList(_) | @sh.EMap(_) =>
      raise @sh.ExError(
        message="a list or map literal has no place in an expression",
        help="build a collection with the receiver methods — `it.xs.push(v)`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// A binding's name with its sigil, added only if it is not already there.
fn sigil(name : String) -> String {
  if name.has_prefix("@") || name.has_prefix("^") {
    name
  } else {
    "@" + name
  }
}

///|
/// `e.value` reads the DOM event; every other member is a binding's.
fn print_member(base : @sh.Ex, m : String) -> String raise @sh.ExError {
  match base {
    @sh.EName("e") => "e." + m
    // The sigil goes on once. A name that already carries one was placed by a
    // binder that knows better — a loop's `@value`, a macro's `^param` — and
    // adding a second gives `@@value`, which reaches no reader.
    @sh.EName(b) => sigil(b) + "." + m
    @sh.EMember(@sh.EName("e"), a) => "e." + a + "." + m
    // A field BELOW an index: `it.rows[i].inner`. The old notation writes the
    // same path, and a `&` reference is the one position that takes one — the
    // runtime `Path` is field-then-key, so a key followed by a field is a step
    // it has.
    @sh.EIndex(_, _) => print_ex(base) + "." + m
    _ =>
      raise @sh.ExError(
        message="a member read needs a binding, an index or the event to read it from",
        help="`it.a.b` is refused: render the child as a component, or name the value with a `compute`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// A call: a builtin printed as its prefix form, anything else as a `$method`.
fn print_call(
  callee : @sh.Ex,
  args : Array[@sh.Arg],
) -> String raise @sh.ExError {
  let pos = positional(args)
  match callee {
    // `math.max(a, b)` and friends: a namespace, because they have no receiver
    @sh.EMember(@sh.EName("math"), name) => {
      guard ["max", "min", "clamp"].contains(name) else {
        raise @sh.ExError(
          message="`math.\{name}` is not one of the builtins",
          help="the numeric builtins are `math.min`, `math.max` and `math.clamp`",
          span=@report.Span::at(0),
        )
      }
      "(" + name + " " + join_args(pos) + ")"
    }
    // a receiver method: either a builtin observation or a `$method` call
    @sh.EMember(recv, name) =>
      match builtin_prefix(name) {
        Some(word) => {
          let head = print_ex(recv)
          if pos.is_empty() {
            "(" + word + " " + head + ")"
          } else {
            "(" + word + " " + head + " " + join_args(pos) + ")"
          }
        }
        None =>
          raise @sh.ExError(
            message="`\{name}` is not a method of a value",
            help="the reading vocabulary is closed — a derivation of your own is a `compute`, called as `\{name}(…)`",
            span=@report.Span::at(0),
          )
      }
    // A bare name: the component's own `compute`. With no arguments it is
    // `$name`, which is what a slot reads; WITH them it is an application, and
    // `$name a b` parses nowhere — `$` always takes a bare name and has no
    // place to put an argument.
    @sh.EName(f) =>
      if pos.is_empty() {
        "$" + f
      } else {
        "(" + f + " " + join_args(pos) + ")"
      }
    _ =>
      raise @sh.ExError(
        message="only a name or a method can be called",
        help="write `name(…)` for a compute, or `value.method(…)` for a builtin",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The prefix word a receiver method prints as.
fn builtin_prefix(name : String) -> String? {
  match name {
    "is_empty" => Some("empty?")
    "is_truthy" => Some("truthy?")
    "is_null" => Some("null?")
    "length" => Some("len")
    "has" => Some("has")
    "contains" => Some("contains")
    "to_string" => Some("str")
    "to_int" => Some("int")
    "to_number" => Some("num")
    "lower" => Some("lower")
    "upper" => Some("upper")
    "trim" => Some("trim")
    _ => None
  }
}

///|
/// A binary operator, with `x == none` folded into the shape predicate the
/// target language has for it.
fn print_bin(op : String, a : @sh.Ex, b : @sh.Ex) -> String raise @sh.ExError {
  if b is @sh.ENone {
    return match op {
      "==" => "(null? " + print_ex(a) + ")"
      "!=" => "(not (null? " + print_ex(a) + "))"
      _ =>
        raise @sh.ExError(
          message="`none` compares with `==` and `!=` only",
          help="write `x == none` or `x != none`",
          span=@report.Span::at(0),
        )
    }
  }
  // A write is not a value: it reaches the printer only from an event
  // option, which prints it as a property action rather than through here.
  if op is (":=" | "+=" | "-=" | "*=" | "/=") {
    raise @sh.ExError(
      message="a write is not a value",
      help="write to a property in an event — `~on_input: it.query := e.value` — or read one here",
      span=@report.Span::at(0),
    )
  }
  let word = match op {
    "==" => "is"
    "!=" => "is not"
    "&&" => "and"
    "||" => "or"
    other => other
  }
  "(" + print_ex(a) + " " + word + " " + print_ex(b) + ")"
}

///|
/// A string template, which is one string with holes in the target too.
fn print_template(parts : Array[@sh.TPart]) -> String raise @sh.ExError {
  let out = StringBuilder()
  out.write_string("$'")
  for p in parts {
    match p {
      @sh.TText(t) => out.write_string(escape_in_template(t))
      @sh.THole(e) => {
        out.write_string("{")
        // A hole is already a call site, so a `compute` in one is named
        // rather than called: `$name` inside a template would be asking the
        // render stack from a body that runs after it.
        out.write_string(
          match e {
            @sh.ECall(@sh.EName(f), args) if positional(args).is_empty() => f
            other => print_ex(other)
          },
        )
        out.write_string("}")
      }
    }
  }
  out.write_string("'")
  out.to_string()
}

///|
/// The positional arguments of a call, refusing a keyword one — a value
/// position has no place for an option.
fn positional(args : Array[@sh.Arg]) -> Array[@sh.Ex] {
  let out = []
  for a in args {
    if a is @sh.APos(e) {
      out.push(e)
    }
  }
  out
}

///|
fn join_args(args : Array[@sh.Ex]) -> String raise @sh.ExError {
  let parts = []
  for a in args {
    parts.push(print_ex(a))
  }
  parts.join(" ")
}

///|
/// A number, whole where it is whole, because `1.0` and `1` read differently
/// in a template.
pub fn num_text(n : Double) -> String {
  if n == n.trunc() && n.abs() < 1.0e15 {
    let i = n.to_int()
    "\{i}"
  } else {
    "\{n}"
  }
}

///|
/// A single-quoted string, with an interior quote escaped.
pub fn quote_str(s : String) -> String {
  let out = StringBuilder()
  out.write_string("'")
  for c in s {
    if c == '\'' {
      out.write_string("\\'")
    } else {
      out.write_char(c)
    }
  }
  out.write_string("'")
  out.to_string()
}

///|
/// Text inside a `$'…'`, where a brace opens a hole and a quote ends it.
fn escape_in_template(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '\'' => out.write_string("\\'")
      '{' => out.write_string("\\{")
      '}' => out.write_string("\\}")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}
