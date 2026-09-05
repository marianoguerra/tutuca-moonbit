// An expression printed back into the notation the slot and script parsers
// read.
//
// Everything is parenthesised that could be: the target language requires
// parentheses wherever precedence would be implicit, and a printer that
// guessed which ones were unnecessary would be a second precedence table to
// keep in step with the first.

///|
/// Print an expression as tutuca source.
pub fn print_ex(ex : Ex) -> String raise ExError {
  match ex {
    ENum(n) => num_text(n)
    EStr(s) => quote_str(s)
    EBool(b) => if b { "true" } else { "false" }
    ENone =>
      raise ExError(
        message="`none` is not a value here",
        help="ask about absence instead: `x == none` reads as `null? x`",
        span=@report.Span::at(0),
      )
    EName(n) => n
    EIt(f) => "." + f
    EState(f) => "state." + f
    EDyn(n) => "*" + n
    EMember(base, m) => print_member(base, m)
    EIndex(base, k) => print_ex(base) + "[" + print_ex(k) + "]"
    ECall(callee, args) => print_call(callee, args)
    EBin(op, a, b) => print_bin(op, a, b)
    EUn("!", a) => "(not " + print_ex(a) + ")"
    EUn("-", a) => "-" + print_ex(a)
    EUn(op, _) =>
      raise ExError(
        message="`\{op}` is not a prefix operator",
        help="the prefix operators are `!` and `-`",
        span=@report.Span::at(0),
      )
    EIf(c, a, b) =>
      "if " +
      print_ex(c) +
      " { " +
      print_ex(a) +
      " } else { " +
      print_ex(b) +
      " }"
    ETemplate(parts) => print_template(parts)
    EList(_) | EMap(_) =>
      raise ExError(
        message="a list or map literal has no place in an expression",
        help="build a collection with the receiver methods — `it.xs.push(v)`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// `e.value` reads the DOM event; every other member is a binding's.
fn print_member(base : Ex, m : String) -> String raise ExError {
  match base {
    EName("e") => "e." + m
    EName(b) => "@" + b + "." + m
    EMember(EName("e"), a) => "e." + a + "." + m
    _ =>
      raise ExError(
        message="a member read needs a binding or the event to read it from",
        help="`it.a.b` is refused: render the child as a component, or name the value with a `compute`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// A call: a builtin printed as its prefix form, anything else as a `$method`.
fn print_call(callee : Ex, args : Array[Arg]) -> String raise ExError {
  let pos = positional(args)
  match callee {
    // `math.max(a, b)` and friends: a namespace, because they have no receiver
    EMember(EName("math"), name) => {
      guard ["max", "min", "clamp"].contains(name) else {
        raise ExError(
          message="`math.\{name}` is not one of the builtins",
          help="the numeric builtins are `math.min`, `math.max` and `math.clamp`",
          span=@report.Span::at(0),
        )
      }
      "(" + name + " " + join_args(pos) + ")"
    }
    // a receiver method: either a builtin observation or a `$method` call
    EMember(recv, name) =>
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
          raise ExError(
            message="`\{name}` is not a method of a value",
            help="the reading vocabulary is closed — a derivation of your own is a `compute`, called as `\{name}(…)`",
            span=@report.Span::at(0),
          )
      }
    // a bare name: the component's own `compute`
    EName(f) =>
      if pos.is_empty() {
        "$" + f
      } else {
        "$" + f + " " + join_args(pos)
      }
    _ =>
      raise ExError(
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
fn print_bin(op : String, a : Ex, b : Ex) -> String raise ExError {
  if b is ENone {
    return match op {
      "==" => "(null? " + print_ex(a) + ")"
      "!=" => "(not (null? " + print_ex(a) + "))"
      _ =>
        raise ExError(
          message="`none` compares with `==` and `!=` only",
          help="write `x == none` or `x != none`",
          span=@report.Span::at(0),
        )
    }
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
fn print_template(parts : Array[TPart]) -> String raise ExError {
  let out = StringBuilder()
  out.write_string("$'")
  for p in parts {
    match p {
      TText(t) => out.write_string(escape_in_template(t))
      THole(e) => {
        out.write_string("{")
        out.write_string(print_ex(e))
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
fn positional(args : Array[Arg]) -> Array[Ex] {
  let out = []
  for a in args {
    if a is APos(e) {
      out.push(e)
    }
  }
  out
}

///|
fn join_args(args : Array[Ex]) -> String raise ExError {
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
